// Requires a desktop AIR SDK and a desktop session. Sends only to loopback.
const assert = require('node:assert/strict');
const http = require('node:http');
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const path = require('node:path');

async function main() {
    assert.ok(process.env.ADL, 'Set ADL to the desktop AIR SDK bin/adl');
    const events = [], failures = [];
    const server = http.createServer((req, res) => {
        if (req.url === '/crossdomain.xml') {
            res.end('<cross-domain-policy><allow-access-from domain="*"/><allow-http-request-headers-from domain="*" headers="*"/></cross-domain-policy>');
            return;
        }
        const chunks = [];
        req.on('data', chunk => chunks.push(chunk));
        req.on('end', () => {
            try { events.push(JSON.parse(Buffer.concat(chunks).toString('utf8').split('\n')[2])); }
            catch (error) { failures.push(error.message); }
            res.end('ok');
        });
    });
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    let child, deadline, logs = '';
    try {
        child = spawn(process.env.ADL, [path.resolve('build/air-exceptions.xml'), '--', String(server.address().port)],
            {stdio: ['ignore', 'pipe', 'pipe']});
        child.stdout.on('data', chunk => { logs += chunk; });
        child.stderr.on('data', chunk => { logs += chunk; });
        deadline = setTimeout(() => child.kill('SIGKILL'), 12000);
        const [code, signal] = await once(child, 'exit');
        assert.equal(code, 0, `AIR exited ${code}/${signal}\n${logs}`);
        assert.deepEqual(failures, []);
        assert.equal(events.length, 3, 'Native Error, Haxe exception chain and string each produce an event');
        const native = events[0].exception.values[0];
        assert.equal(native.type, 'TypeError');
        assert.equal(native.value, 'native Flash failure');
        assert.equal(native.mechanism.handled, false);
        const frame = native.stacktrace.frames.find(frame => frame.module === 'FlashExceptionRuntimeTest' && frame.function === 'nativeFailure');
        assert.ok(frame, 'AVM2 class and method are separated');
        assert.equal(frame.platform, 'java');
        assert.ok(frame.lineno > 0, 'Actual debug source line is preserved');
        assert.equal(events[0].debug_meta.images[0].uuid, '1a876fc1-6ef9-4b93-9f35-11784da018ef');
        assert.deepEqual(events[1].exception.values.map(value => value.value), ['root', 'outer']);
        assert.equal(events[2].exception.values[0].value, 'string failure');
        assert.equal(events[2].debug_meta, undefined, 'Scalar errors do not invent a stack');
        console.log('PASS AIR: native Error, Haxe exception chain, scalar error and ProGuard metadata');
    } finally {
        clearTimeout(deadline);
        if (child && child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
        server.close();
    }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
