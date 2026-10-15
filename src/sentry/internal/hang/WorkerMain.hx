package sentry.internal.hang;

#if flash
/** Build as a SEPARATE SWF; never run the game's entry point inside a worker. */
class WorkerMain {
    static var timer:haxe.Timer;
    static function main():Void {
        var worker = flash.system.Worker.current;
        if (worker.isPrimordial) return;
        try {
            var config:Dynamic = worker.getSharedProperty("sentry.hang.config");
            var settings = new HangSettings(config.settings, config.settings.sampleRate);
            var observer = new HangObserver(settings);
            var backend = new sentry.backend.EnvelopeBackend(new sentry.internal.Config({
                dsn: config.dsn, maxQueueSize: 2, requestTimeoutMs: config.requestTimeoutMs,
                onError: function(message) worker.setSharedProperty("sentry.hang.error", message)
            }), new sentry.transport.HttpTransport());
            timer = new haxe.Timer(settings.heartbeatIntervalMs);
            timer.run = function() {
                if (worker.getSharedProperty("sentry.hang.stop") == true) {
                    timer.stop();
                    backend.close(config.shutdownTimeoutMs, function(_) worker.terminate());
                    return;
                }
                var now = Date.now().getTime();
                var signal:HangSignal = worker.getSharedProperty("sentry.hang.signal");
                if (signal != null) {
                    var recovered = observer.receive(signal, now);
                    if (recovered != null) backend.capture(HangEvents.materialize(recovered, now, true), []);
                }
                // Match Cocoa V2: retain the detected incident and send it once after recovery.
                // An in-process Worker cannot observe the death of its own AIR runtime.
                observer.poll(now);
            };
            worker.setSharedProperty("sentry.hang.status", "ready");
        } catch (error:Dynamic) {
            worker.setSharedProperty("sentry.hang.error", Std.string(error));
            worker.setSharedProperty("sentry.hang.status", "failed");
            if (timer != null) timer.stop();
        }
    }
}
#end
