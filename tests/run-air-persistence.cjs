// Loopback only. Suspend and terminate our own AIR fixture, then relaunch the same application.
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const {spawn, execFileSync} = require('node:child_process');
const {once} = require('node:events');
const {setTimeout: delay} = require('node:timers/promises');

async function until(predicate, label, timeout = 6000) {
    const started = Date.now();
    while (!predicate()) {
        if (Date.now() - started > timeout) throw new Error(`Timed out: ${label}`);
        await delay(25);
    }
}
function alive(pid) {
    try { process.kill(pid, 0); return true; }
    catch (error) { return error.code !== 'ESRCH'; }
}
function helperPid(parentPid) {
    const matches = execFileSync('ps', ['-axo', 'pid=,ppid=,comm='], {encoding: 'utf8'})
        .split('\n').map(line => line.match(/^\s*(\d+)\s+(\d+)\s+(.+)$/))
        .filter(match => match && Number(match[2]) === parentPid && /node(?:$|[-\s])/.test(match[3]));
    assert.equal(matches.length, 1, 'The AIR example must start one Node child');
    return Number(matches[0][1]);
}
async function main() {
    assert.ok(process.env.ADL, 'Set ADL to the desktop AIR SDK bin/adl');
    assert.notEqual(process.platform, 'win32', 'This fixture uses POSIX process signals');
    const reports = [], runs = [], children = [], helpers = [];
    let current, killTimer, fixtureError;
    const server = http.createServer((req, res) => {
        const url = new URL(req.url, 'http://localhost');
        if (url.pathname === '/crossdomain.xml') {
            res.setHeader('Content-Type', 'text/xml');
            res.end('<cross-domain-policy><allow-access-from domain="*"/><allow-http-request-headers-from domain="*" headers="*"/></cross-domain-policy>');
            return;
        }
        if (url.pathname === '/checkpoint') {
            const run = current;
            const state = url.searchParams.get('state');
            run.checkpoints.push({state, time: Date.now()});
            if (state === 'armed') {
                try {
                    run.helper = helperPid(run.child.pid); helpers.push(run.helper);
                    assert.equal(url.searchParams.get('mode'), 'external');
                    if (run.index === 0) {
                        run.child.kill('SIGSTOP');
                        killTimer = setTimeout(() => {
                            run.reportsBeforeDeath = reports.length;
                            run.killedAt = Date.now();
                            run.child.kill('SIGKILL');
                        }, 1100);
                    }
                } catch (error) { fixtureError = error; run.child.kill(); }
            }
            res.end('ok');
            return;
        }
        const chunks = [];
        req.on('data', chunk => chunks.push(chunk));
        req.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8');
            reports.push({event: JSON.parse(text.split('\n')[2]), time: Date.now(), text});
            res.end('ok');
        });
    });
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    try {
        for (let index = 0; index < 3; index++) {
            const run = {index, startedAt: Date.now(), checkpoints: [], logs: ''};
            runs.push(run); current = run;
            run.child = spawn(process.env.ADL, ['-profile', 'extendedDesktop', path.resolve('build/air-hangs.xml'), '--',
                'launcher', String(server.address().port), process.execPath, path.resolve('build/sentry-watchdog.cjs')],
                {stdio: ['ignore', 'pipe', 'pipe']});
            children.push(run.child);
            run.child.stdout.on('data', chunk => { run.logs += chunk; });
            run.child.stderr.on('data', chunk => { run.logs += chunk; });
            const timeout = setTimeout(() => run.child.kill('SIGKILL'), 20000);
            const [code, signal] = await once(run.child, 'exit'); clearTimeout(timeout);
            if (fixtureError) throw fixtureError;
            assert.ok(run.helper, `NativeProcess did not start a helper: ${run.logs}`);
            await until(() => !alive(run.helper), 'helper exits after its AIR parent');
            if (index === 0) {
                assert.equal(signal, 'SIGKILL');
                assert.equal(run.reportsBeforeDeath, 0, 'No ongoing event before process death');
                assert.equal(reports.length, 0, 'Fatal hang waits for a subsequent launch');
                await delay(500);
            } else {
                assert.equal(code, 0, `AIR relaunch ${index} failed: ${code}/${signal}\n${run.logs}`);
                assert.equal(reports.length, 1, 'Only one event across subsequent launches');
            }
        }
        const {event, time, text} = reports[0];
        const hang = event.contexts.app_hang;
        assert.equal(event.level, 'fatal');
        assert.equal(event.exception.values[0].type, 'FatalApplicationHang');
        assert.equal(event.exception.values[0].mechanism.handled, false);
        assert.equal(hang.recovered, false);
        assert.equal(hang.end_reason, 'process_exit');
        assert.equal(hang.duration_is_lower_bound, true);
        assert.equal(hang.duration_max_ms, null);
        assert.ok(hang.duration_ms >= 300 && hang.duration_ms < 1600);
        assert.ok(event.timestamp * 1000 < runs[0].killedAt, 'Detection time survives process death');
        assert.ok(time >= runs[1].startedAt, 'Delivery happens on the next launch');
        assert.equal(event.user, null);
        assert.equal(event.contexts.game.room, 'square');
        assert.equal(text.includes('must-be-redacted'), false);
        console.log('PASS AIR persistence: NativeProcess helper, no ongoing upload, one next-launch fatal event, preserved time/context/redaction, no replay after acknowledgement');
    } catch (error) {
        console.error(JSON.stringify({runs: runs.map(({child, ...run}) => run), reports}, null, 2));
        throw error;
    } finally {
        clearTimeout(killTimer);
        for (const child of children) if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
        for (const pid of helpers) if (alive(pid)) process.kill(pid, 'SIGTERM');
        server.close();
    }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
