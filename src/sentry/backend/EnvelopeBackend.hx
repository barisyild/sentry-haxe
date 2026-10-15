package sentry.backend;

import sentry.internal.Config;
import sentry.internal.Values;
import sentry.internal.RateLimits;
import sentry.internal.Envelope;
import sentry.transport.Transport;
import sentry.transport.Response;

class EnvelopeBackend implements Backend {
    final config:Config;
    final transport:Transport;
    final limits = new RateLimits();
    var queue:Array<{event:sentry.Event, attachments:Array<sentry.Attachment>}> = [];
    var active = false;
    var closed = false;
    var accepted = 0;
    var settled = 0;
    var failures = 0;
    var waiters:Array<Void->Void> = [];
    var watchdog:haxe.Timer;

    public function new(config:Config, transport:Transport) { this.config = config; this.transport = transport; }
    public function syncScope(scope:sentry.Scope):Void {}

    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String> {
        if (closed || limits.limited("error", Values.now())) return null;
        if (queue.length + (active ? 1 : 0) >= config.maxQueueSize) { config.report("Envelope queue is full"); return null; }
        event.sdk = {name: "sentry.haxe", version: sentry.Sentry.VERSION};
        // Snapshot attachment bytes as well: callers can reuse their buffers immediately.
        var copies = [for (a in attachments) new sentry.Attachment(a.bytes.sub(0, a.bytes.length), a.filename, a.contentType)];
        queue.push({event: event, attachments: copies});
        accepted++;
        pump();
        return event.event_id;
    }

    function pump():Void {
        if (active || queue.length == 0 || closed) return;
        var item = queue.shift();
        if (limits.limited("error", Values.now())) { settled++; failures++; notifyWaiters(); pump(); return; }
        var attachments = limits.limited("attachment", Values.now()) ? [] : item.attachments;
        active = true;
        var completed = false;
        function complete(response:Response):Void {
            if (completed) return;
            completed = true;
            if (watchdog != null) { watchdog.stop(); watchdog = null; }
            active = false;
            settled++;
            limits.update(response, Values.now());
            if (response.status < 200 || response.status >= 300) {
                failures++;
                config.report("Envelope delivery failed (HTTP " + response.status + ")" + (response.error == null ? "" : ": " + response.error));
            }
            notifyWaiters();
            pump();
        }
        if (config.requestTimeoutMs > 0) watchdog = haxe.Timer.delay(function() complete({status: 0, error: "Request timed out"}), config.requestTimeoutMs);
        try {
            transport.send({url: config.dsn.envelopeUrl, body: Envelope.encode(config.dsn, item.event, attachments), contentType: "application/x-sentry-envelope", timeoutMs: config.requestTimeoutMs}, complete);
        } catch (e:Dynamic) complete({status: 0, error: Std.string(e)});
    }

    function notifyWaiters():Void { for (check in waiters.copy()) check(); }

    public function flush(timeoutMs:Int, done:Bool->Void):Void {
        var target = accepted;
        var initialFailures = failures;
        if (settled >= target) { done(true); return; }
        if (timeoutMs <= 0) { done(false); return; }
        var timer:haxe.Timer = null;
        var finished = false;
        var check:Void->Void = null;
        function finish(ok:Bool):Void {
            if (finished) return;
            finished = true;
            if (timer != null) timer.stop();
            waiters.remove(check);
            done(ok);
        }
        check = function() { if (settled >= target) finish(failures == initialFailures); };
        waiters.push(check);
        timer = haxe.Timer.delay(function() finish(false), timeoutMs);
    }

    public function close(timeoutMs:Int, done:Bool->Void):Void {
        flush(timeoutMs, function(ok) {
            closed = true;
            queue = [];
            if (watchdog != null) watchdog.stop();
            transport.close();
            failures++;
            settled = accepted;
            notifyWaiters();
            done(ok);
        });
    }
}
