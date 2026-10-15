package sentry.integrations;

#if flash
import sentry.internal.hang.*;

/** Explicit opt-in. Dispose before unloading a SWF; Client.close also disposes it. */
class FlashHangMonitor {
    public var mode(default, null):String = "recovery";
    final client:sentry.Client;
    final stage:flash.display.Stage;
    final settings:HangSettings;
    final options:FlashHangOptions;
    final recovery:HangRecovery;
    var timer:haxe.Timer;
    var external:ExternalWatchdogLink;
    var paused = false;
    var inactive = false;
    var stopped = false;
    var stopFinished = false;
    var stopCallbacks:Array<Void->Void> = [];
    var closeHandler:(Void->Void)->Void;
    var sequence = 0;
    var oversizeReported = false;
    #if flash11_4
    var worker:flash.system.Worker;
    var workerStarted:Float;
    var workerError:String;
    #end

    public static function install(stage:flash.display.Stage, ?options:FlashHangOptions, ?client:sentry.Client):FlashHangMonitor {
        return new FlashHangMonitor(stage, options == null ? {} : options, client == null ? sentry.Sentry.getClient() : client);
    }

    function new(stage:flash.display.Stage, options:FlashHangOptions, client:sentry.Client) {
        if (stage == null) throw new haxe.Exception("FlashHangMonitor requires a stage");
        this.stage = stage;
        this.options = options;
        this.client = client;
        settings = new HangSettings(options, client.config.sampleRate);
        recovery = new HangRecovery(settings);
        paused = options.initiallyPaused == true;
        if (options.externalPort != null) external = new ExternalWatchdogLink(options.externalPort, options.externalToken, settings, client.config.report);
        if (client.stopHangMonitor != null) client.stopHangMonitor(function() {});
        if (!client.enabled) { stopped = stopFinished = true; mode = "stopped"; return; }
        closeHandler = function(done) stop(done);
        client.stopHangMonitor = closeHandler;
        if (client.config.options.transport != null) {
            external = null;
            client.config.report("Custom transport cannot cross Flash workers/processes; using recovery detection");
        } else if (external == null) startWorker();
        if (stopped || !client.enabled) return;
        if (options.pauseWhenInactive != false) {
            stage.addEventListener(flash.events.Event.DEACTIVATE, deactivate);
            stage.addEventListener(flash.events.Event.ACTIVATE, activate);
        }
        timer = new haxe.Timer(settings.heartbeatIntervalMs);
        timer.run = beat;
        beat();
    }

    function startWorker():Void {
        #if flash11_4
        var bytes = options.workerBytes == null ? haxe.Resource.getBytes("sentry-hang-worker") : options.workerBytes;
        if (bytes == null) return;
        try {
            if (!flash.system.Worker.isSupported) { client.config.report("Flash Worker is unsupported; using recovery detection"); return; }
            // Only our application-sandbox code may give the embedded helper AIR privileges.
            var appSandbox = flash.system.Security.sandboxType == flash.system.Security.APPLICATION;
            worker = flash.system.WorkerDomain.current.createWorker(bytes.getData(), appSandbox);
            worker.setSharedProperty("sentry.hang.config", {
                dsn: client.config.dsn.publicDsn,
                requestTimeoutMs: client.config.requestTimeoutMs,
                shutdownTimeoutMs: client.config.shutdownTimeoutMs,
                settings: settings.serialize()
            });
            workerStarted = Date.now().getTime();
            worker.start();
        } catch (error:Dynamic) {
            abandonWorker();
            client.config.report("Cannot start hang worker; using recovery detection: " + Std.string(error));
        }
        #end
    }

    function beat():Void {
        if (stopped) return;
        if (!client.enabled) { stop(); return; }
        var now = Date.now().getTime();
        var nextMode = "recovery";
        if (external != null && external.ready) nextMode = "external";
        #if flash11_4
        if (worker != null) {
            try {
                var status:String = worker.getSharedProperty("sentry.hang.status");
                if (status == "ready") nextMode = "worker";
                else if (status == "failed" || worker.state == flash.system.WorkerState.TERMINATED
                    || now - workerStarted > Math.max(5000, settings.thresholdMs * 2)) {
                    abandonWorker();
                    client.config.report("Hang worker stopped or failed to initialize; using recovery detection");
                }
                if (worker != null) {
                    var error:String = worker.getSharedProperty("sentry.hang.error");
                    if (error != null && error != workerError) { workerError = error; client.config.report(error); }
                }
            } catch (_:Dynamic) { abandonWorker(); nextMode = "recovery"; }
        }
        #end
        if (nextMode != mode) { mode = nextMode; recovery.reset(); }
        var active = !paused && !inactive;
        var event = active ? client.prepareHangSnapshot(HangEvents.template(mode, settings.thresholdMs, settings.heartbeatIntervalMs)) : null;
        // A beforeSend hook may close/reinitialize the client.
        if (stopped || !client.enabled) return;
        if (event != null && haxe.io.Bytes.ofString(sentry.internal.ProtocolJson.stringify(event)).length > HangSettings.MAX_SNAPSHOT_BYTES) {
            event = null;
            if (!oversizeReported) { oversizeReported = true; client.config.report("Hang snapshot exceeds 256 KiB; snapshot discarded"); }
        }
        var signal:HangSignal = {sequence: sequence++, active: active, event: event};
        if (mode == "recovery") {
            var incident = recovery.beat(signal, now);
            if (incident != null) client.capturePreparedHang(HangEvents.materialize(incident, now, true));
        }
        #if flash11_4
        if (worker != null) try worker.setSharedProperty("sentry.hang.signal", signal) catch (_:Dynamic) {
            abandonWorker(); mode = "recovery"; recovery.reset();
        }
        #end
        if (external != null) external.beat(signal, now);
    }

    #if flash11_4
    function abandonWorker():Void {
        if (worker != null) try worker.terminate() catch (_:Dynamic) {}
        worker = null;
    }
    #end
    function deactivate(_:flash.events.Event):Void { inactive = true; recovery.reset(); beat(); }
    function activate(_:flash.events.Event):Void { inactive = false; recovery.reset(); beat(); }
    public function pause():Void { paused = true; recovery.reset(); beat(); }
    public function resume():Void { paused = false; recovery.reset(); beat(); }

    public function stop(?done:Void->Void):Void {
        if (stopFinished) { if (done != null) done(); return; }
        if (done != null) stopCallbacks.push(done);
        if (stopped) return;
        stopped = true;
        mode = "stopped";
        if (timer != null) timer.stop();
        stage.removeEventListener(flash.events.Event.DEACTIVATE, deactivate);
        stage.removeEventListener(flash.events.Event.ACTIVATE, activate);
        if (external != null) external.stop();
        #if flash11_4
        if (worker != null) {
            var closingWorker = worker;
            worker = null;
            try {
                closingWorker.setSharedProperty("sentry.hang.stop", true);
                var deadline = Date.now().getTime() + settings.heartbeatIntervalMs + client.config.shutdownTimeoutMs + 250;
                var wait = new haxe.Timer(50);
                wait.run = function() {
                    var complete = false;
                    try complete = closingWorker.state == flash.system.WorkerState.TERMINATED
                        || closingWorker.getSharedProperty("sentry.hang.status") == "failed" catch (_:Dynamic) complete = true;
                    if (complete || Date.now().getTime() >= deadline) {
                        wait.stop();
                        try closingWorker.terminate() catch (_:Dynamic) {}
                        finishStop();
                    }
                };
                return;
            } catch (_:Dynamic) { try closingWorker.terminate() catch (_:Dynamic) {} }
        }
        #end
        finishStop();
    }

    function finishStop():Void {
        stopFinished = true;
        if (client.stopHangMonitor == closeHandler) client.stopHangMonitor = null;
        var callbacks = stopCallbacks;
        stopCallbacks = [];
        for (callback in callbacks) callback();
    }
}
#end
