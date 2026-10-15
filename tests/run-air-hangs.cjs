// Requires a desktop AIR SDK and an interactive desktop session. Never sends outside loopback.
const assert = require('node:assert/strict');
const http = require('node:http');
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');

async function until(predicate, label, timeout = 6000) {
    const start = Date.now();
    while (!predicate()) {
        if (Date.now() - start > timeout) throw new Error(`Timed out: ${label}`);
        await delay(25);
    }
}
async function main() {
    const adl = process.env.ADL;
    assert.ok(adl, 'Set ADL to the desktop AIR SDK bin/adl');
    const children = [];
    const observations = [];
    let current, resumeTimer;
    const server = http.createServer((req, res) => {
        const url = new URL(req.url, 'http://localhost');
        if (url.pathname === '/checkpoint') {
            const checkpoint = {state: url.searchParams.get('state'), mode: url.searchParams.get('mode'), time: Date.now()};
            current.checkpoints.push(checkpoint);
            if (['external', 'launcher'].includes(current.scenario) && checkpoint.state === 'armed') {
                // Suspend ONLY our test AIR process; the watchdog remains an independent process.
                current.child.kill('SIGSTOP');
                resumeTimer = setTimeout(() => current.child.kill('SIGCONT'), 1100);
            }
            res.end('ok');
            return;
        }
        if (url.pathname === '/crossdomain.xml') {
            res.setHeader('Content-Type', 'text/xml');
            res.end('<cross-domain-policy><allow-access-from domain="*"/><allow-http-request-headers-from domain="*" headers="*"/></cross-domain-policy>');
            return;
        }
        const chunks = [];
        req.on('data', data => chunks.push(data));
        req.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8');
            current.reports.push({event: JSON.parse(text.split('\n')[2]), time: Date.now(), text});
            res.end('ok');
        });
    });
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const port = server.address().port;
    try {
        const cases = ['worker', 'recovery', 'paused', 'stopped', 'filtered', 'oversize'];
        if (process.platform !== 'win32') cases.push('external', 'launcher');
        for (const scenario of cases) {
            current = {scenario, reports: [], checkpoints: [], logs: ''};
            observations.push(current);
            const args = [path.resolve('build/air-hangs.xml'), '--', scenario, String(port)];
            if (scenario === 'launcher') {
                args.unshift('-profile', 'extendedDesktop');
                args.push(process.execPath, path.resolve('build/sentry-watchdog.cjs'));
            }
            let watcher;
            if (scenario === 'external') {
                watcher = spawn(process.execPath, [path.resolve('build/sentry-watchdog.cjs'), '--dsn', `http://public@127.0.0.1:${port}/42`], {stdio: ['ignore', 'pipe', 'pipe']});
                children.push(watcher);
                let buffer = '', handshake;
                watcher.stdout.on('data', chunk => {
                    buffer += chunk;
                    let newline;
                    while ((newline = buffer.indexOf('\n')) >= 0) {
                        const event = JSON.parse(buffer.slice(0, newline)); buffer = buffer.slice(newline + 1);
                        if (event.type === 'listening') handshake = event;
                    }
                });
                watcher.stderr.on('data', chunk => { current.logs += chunk; });
                await until(() => handshake, 'external watchdog startup');
                args.push(String(handshake.port), handshake.token);
            }
            const child = spawn(adl, args, {stdio: ['ignore', 'pipe', 'pipe']});
            children.push(child); current.child = child;
            child.stdout.on('data', chunk => { current.logs += chunk; });
            child.stderr.on('data', chunk => { current.logs += chunk; });
            const timeout = setTimeout(() => { child.kill('SIGCONT'); child.kill('SIGTERM'); }, 20000);
            const [code, signal] = await once(child, 'exit');
            clearTimeout(timeout); clearTimeout(resumeTimer);
            assert.equal(code, 0, `${scenario}: AIR exited ${code}/${signal}\n${current.logs}`);
            const armed = current.checkpoints.find(item => item.state === 'armed');
            const resumed = current.checkpoints.find(item => item.state === 'resumed');
            assert.ok(armed && resumed, `${scenario}: missing checkpoints\n${current.logs}`);
            if (['paused', 'stopped', 'filtered', 'oversize'].includes(scenario)) {
                assert.equal(current.reports.length, 0, `${scenario}: must not report`);
            } else {
                assert.equal(armed.mode, scenario === 'launcher' ? 'external' : scenario);
                assert.equal(current.reports.length, 1, `${scenario}: exactly one finalized hang event\n${current.logs}`);
                const report = current.reports[0];
                assert.ok(report.time >= armed.time);
                assert.ok(report.time >= resumed.time - 100, `${scenario}: no ongoing event is sent while blocked`);
                assert.equal(report.event.user, null);
                assert.equal(report.event.contexts.game.room, 'square');
                assert.equal(report.event.breadcrumbs[0].message, 'Entered square');
                assert.equal(report.event.contexts.app_hang.recovered, true);
                assert.equal(report.text.includes('must-be-redacted'), false);
                const recovered = current.reports.at(-1);
                assert.equal(recovered.event.contexts.app_hang.recovered, true);
                assert.equal(recovered.event.tags['hang.status'], 'recovered');
                assert.ok(recovered.event.contexts.app_hang.duration_ms >= 1000);
                assert.equal(recovered.event.contexts.game.room, 'square');
                assert.equal(recovered.text.includes('must-be-redacted'), false);
                assert.equal(recovered.event.level, 'error');
                assert.equal(recovered.event.contexts.app_hang.initial_event_id, undefined);
                assert.ok(recovered.event.contexts.app_hang.duration_min_ms <= recovered.event.contexts.app_hang.duration_ms);
                assert.ok(recovered.event.contexts.app_hang.duration_max_ms >= recovered.event.contexts.app_hang.duration_ms);
            }
            if (watcher) {
                await until(() => watcher.exitCode !== null, 'watchdog clean shutdown');
                assert.equal(watcher.exitCode, 0);
            }
            console.log(`PASS AIR ${scenario}: ${current.reports.length} report(s)`);
        }
    } catch (error) {
        console.error(JSON.stringify(observations.map(({scenario, checkpoints, reports, logs}) => ({scenario, checkpoints, reports, logs})), null, 2));
        throw error;
    } finally {
        clearTimeout(resumeTimer);
        for (const child of children) if (child.exitCode === null) { child.kill('SIGCONT'); child.kill('SIGTERM'); }
        server.close();
    }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
