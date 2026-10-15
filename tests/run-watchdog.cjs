// Loopback only. Exercises the pending -> finalized event lifecycle across process restarts.
const assert = require('node:assert/strict');
const http = require('node:http');
const net = require('node:net');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const {setTimeout: delay} = require('node:timers/promises');

async function until(predicate, label, timeout = 5000) {
    const start = Date.now();
    while (!predicate()) {
        if (Date.now() - start > timeout) throw new Error(`Timed out: ${label}`);
        await delay(20);
    }
}
async function main() {
    const cache = fs.mkdtempSync(path.join(os.tmpdir(), 'sentry-watchdog-test-'));
    const reports = [], children = [], connections = [];
    let failNext = false, sequence = 0;
    const server = http.createServer((req, res) => {
        const chunks = [];
        req.on('data', data => chunks.push(data));
        req.on('end', () => {
            const lines = Buffer.concat(chunks).toString('utf8').split('\n');
            assert.equal(JSON.parse(lines[1]).length, Buffer.byteLength(lines[2]));
            reports.push(JSON.parse(lines[2]));
            res.statusCode = failNext ? 503 : 200;
            failNext = false;
            res.end('ok');
        });
    });
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    function records() {
        return fs.readdirSync(cache, {recursive: true}).filter(name => name.endsWith('.json')).map(name => {
            try { return JSON.parse(fs.readFileSync(path.join(cache, name), 'utf8')); }
            catch { return null; }
        }).filter(Boolean);
    }
    async function start(parentPid = 0) {
        const args = [path.resolve(process.env.WATCHDOG || 'build/sentry-watchdog.cjs'), '--dsn',
            `http://public@127.0.0.1:${server.address().port}/42`, '--cache-dir', cache];
        if (parentPid) args.push('--parent-pid', String(parentPid));
        const child = spawn(process.execPath, args, {stdio: ['ignore', 'pipe', 'pipe']});
        children.push(child);
        let pending = '', ready, errors = '';
        child.stderr.on('data', data => { errors += data; });
        child.stdout.on('data', data => {
            pending += data;
            let i;
            while ((i = pending.indexOf('\n')) >= 0) {
                const item = JSON.parse(pending.slice(0, i)); pending = pending.slice(i + 1);
                if (item.type === 'listening') ready = item;
            }
        });
        await until(() => ready || child.exitCode !== null, 'watchdog start');
        assert.ok(ready, errors);
        return {child, ready};
    }
    async function connect(ready, badToken = false) {
        const socket = net.createConnection({host: '127.0.0.1', port: ready.port}); connections.push(socket);
        await once(socket, 'connect'); socket.setEncoding('utf8');
        const reply = once(socket, badToken ? 'close' : 'data');
        const hello = JSON.stringify({type: 'hello', version: 1, token: badToken ? 'wrong' : ready.token,
            settings: {thresholdMs: 300, heartbeatIntervalMs: 50, cooldownMs: 0, maxRecoveryGapMs: 1000, sampleRate: 1}}) + '\n';
        socket.write(hello.slice(0, 10)); socket.write(hello.slice(10));
        const response = await reply;
        if (!badToken) assert.equal(JSON.parse(response[0]).type, 'ready');
        return socket;
    }
    function beat(socket, active = true, event = {
        event_id: '0123456789abcdef0123456789abcdef', timestamp: Date.now() / 1000, platform: 'other',
        message: {formatted: 'İstanbul 😀'}, level: 'error', user: null,
        tags: {'hang.monitor': 'external', 'hang.status': 'ongoing', 'hang.id': ''},
        contexts: {app_hang: {type: 'app_hang', duration_ms: 0, snapshot_age_ms: 0, recovered: false,
            hang_id: '', status: 'ongoing', duration_min_ms: 0, duration_max_ms: null,
            duration_is_lower_bound: true, end_reason: null}}
    }) {
        socket.write(JSON.stringify({type: 'beat', signal: {sequence: sequence++, active, event}}) + '\n');
    }
    async function stop(socket, child) {
        const exited = once(child, 'exit'); socket.write('{"type":"stop"}\n');
        assert.equal((await exited)[0], 0);
    }
    try {
        const first = await start(); await connect(first.ready, true);
        assert.equal(records().length, 0, 'Bad authentication cannot stage an event');
        const socket = await connect(first.ready);
        for (let i = 0; i < 8; i++) { beat(socket); await delay(50); }
        assert.equal(reports.length, 0);
        await until(() => records().some(r => r.incident), 'pending hang on disk');
        const staged = records()[0];
        assert.ok(staged.incident.durationMs >= 300);
        assert.equal(staged.incident.event.user, null, 'Only the filtered snapshot is persisted');
        await delay(250);
        assert.equal(reports.length, 0, 'No event is sent while the application is still hanging');
        const concurrent = await start();
        const concurrentSocket = await connect(concurrent.ready);
        await stop(concurrentSocket, concurrent.child);
        assert.equal(reports.length, 0, 'A second live helper cannot consume an active incident');
        beat(socket);
        await until(() => reports.length === 1 && records().length === 0, 'one finalized recovery and cache acknowledgement');
        const recovered = reports[0];
        assert.equal(recovered.event_id, staged.id);
        assert.equal(recovered.timestamp, staged.incident.detectedAtMs / 1000);
        assert.equal(recovered.message.formatted, 'İstanbul 😀');
        assert.equal(recovered.contexts.app_hang.recovered, true);
        assert.equal(recovered.level, 'error');
        assert.equal(recovered.contexts.app_hang.initial_event_id, undefined);
        assert.ok(recovered.contexts.app_hang.duration_ms >= 550);
        assert.equal(recovered.contexts.app_hang.duration_is_lower_bound, false);
        await until(() => records().some(r => r.incident), 'next independent hang');
        beat(socket, false);
        await until(() => records().length === 0, 'inactive transition cancels pending incident');
        beat(socket, true, null); await delay(400);
        assert.equal(records().length, 0); assert.equal(reports.length, 1);
        await stop(socket, first.child);

        const clean = await start(); const cleanSocket = await connect(clean.ready);
        beat(cleanSocket); await until(() => records().some(r => r.incident), 'pending before explicit stop');
        await stop(cleanSocket, clean.child);
        assert.equal(records().length, 0, 'Clean stop clears the pending episode');
        const lost = await start(); const lostSocket = await connect(lost.ready);
        beat(lostSocket); await delay(60);
        const lostExit = once(lost.child, 'exit'); lostSocket.destroy();
        assert.equal((await lostExit)[0], 0);
        assert.equal(records().length, 0, 'Socket loss cannot manufacture a post-exit hang');
        assert.equal(reports.length, 1);

        // Kill only a dummy application process after an independently observed hang.
        const app = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)']); children.push(app);
        const fatal = await start(app.pid); const fatalSocket = await connect(fatal.ready);
        beat(fatalSocket); await until(() => records().some(r => r.incident), 'pending before process death');
        const pendingFatal = records()[0];
        const appExit = once(app, 'exit'), helperExit = once(fatal.child, 'exit');
        app.kill(); await appExit; assert.equal((await helperExit)[0], 0);
        assert.equal(reports.length, 1, 'Fatal hang waits for next launch');
        const cachedFatal = records()[0].incident;
        await delay(450);
        const restarted = await start();
        await until(() => reports.length === 2 && records().length === 0, 'next-launch fatal event');
        assert.equal(reports[1].event_id, pendingFatal.id);
        assert.equal(reports[1].level, 'fatal');
        assert.equal(reports[1].contexts.app_hang.recovered, false);
        assert.equal(reports[1].contexts.app_hang.end_reason, 'process_exit');
        assert.equal(reports[1].contexts.app_hang.duration_ms, cachedFatal.durationMs, 'Restart delay is not hang duration');
        assert.equal(reports[1].contexts.app_hang.duration_max_ms, null);
        assert.equal(reports[1].contexts.app_hang.duration_is_lower_bound, true);
        const restartedSocket = await connect(restarted.ready); await stop(restartedSocket, restarted.child);

        // A failed upload keeps the FINAL outcome, never a fake pending/fatal event.
        const retry = await start(); const retrySocket = await connect(retry.ready);
        beat(retrySocket); await until(() => records().some(r => r.incident), 'pending before transport failure');
        failNext = true; beat(retrySocket);
        await until(() => reports.length === 3 && records().some(r => r.event), 'failed final event retained');
        await stop(retrySocket, retry.child);
        const retryLaunches = await Promise.all([start(), start()]);
        await until(() => reports.length === 4 && records().length === 0, 'one owner replays the failed upload');
        assert.equal(reports[3].event_id, reports[2].event_id);
        assert.equal(reports[3].timestamp, reports[2].timestamp);
        assert.equal(reports[3].contexts.app_hang.recovered, true);
        assert.equal(reports[3].level, 'error');
        for (const item of retryLaunches) await stop(await connect(item.ready), item.child);
        assert.equal(reports.length, 4, 'No duplicate event from concurrent startup');
        // A helper dying while its application lives does not establish a fatal app hang.
        const survivingApp = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)']); children.push(survivingApp);
        const brokenObserver = await start(survivingApp.pid);
        const brokenSocket = await connect(brokenObserver.ready);
        beat(brokenSocket); await until(() => records().some(r => r.incident), 'pending before observer death');
        const observerExit = once(brokenObserver.child, 'exit'); brokenObserver.child.kill('SIGKILL'); await observerExit;
        const replacement = await start(survivingApp.pid);
        await until(() => reports.length === 5 && records().length === 0, 'unresolved observer-loss event');
        assert.equal(reports[4].level, 'error');
        assert.equal(reports[4].tags['hang.status'], 'unresolved');
        assert.equal(reports[4].contexts.app_hang.end_reason, 'observer_lost');
        assert.equal(reports[4].contexts.app_hang.recovered, false);
        await stop(await connect(replacement.ready), replacement.child);
        const survivingExit = once(survivingApp, 'exit'); survivingApp.kill(); await survivingExit;
        console.log('PASS watchdog: pending on disk, one recovery event, next-launch fatal hang, stable IDs/times, upload retry, live-owner isolation, privacy, stop and IPC loss');
    } finally {
        for (const socket of connections) socket.destroy();
        for (const child of children) if (child.exitCode === null) child.kill();
        server.close(); fs.rmSync(cache, {recursive: true, force: true});
    }
}
main().catch(error => {console.error(error); process.exitCode = 1});
