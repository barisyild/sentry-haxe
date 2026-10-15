import sentry.Sentry;
import sentry.integrations.FlashHangMonitor;

/** Run only with tests/run-air-hangs.cjs: bounded intentional stalls, loopback ingest. */
class FlashHangRuntimeTest {
    static var nativeApp:Dynamic;
    static var monitor:FlashHangMonitor;
    static var port:Int;
    static var scenario:String;
    static var loaders:Array<flash.net.URLLoader> = [];
    static var finished = false;
    static var launcher:AirWatchdogLauncher;

    static function main():Void {
        var type:Dynamic = flash.system.ApplicationDomain.currentDomain.getDefinition("flash.desktop.NativeApplication");
        nativeApp = type.nativeApplication;
        nativeApp.addEventListener("invoke", function(event:Dynamic) {
            var args:Array<String> = event.arguments;
            if (args.length < 2) { nativeApp.exit(2); return; }
            scenario = args[0]; port = Std.parseInt(args[1]);
            try run(args) catch (error:Dynamic) checkpoint("error=" + Std.string(error), function() nativeApp.exit(1));
        });
        haxe.Timer.delay(function() { if (!finished) nativeApp.exit(3); }, 15000);
    }

    static function run(args:Array<String>):Void {
        var config:sentry.Options = {dsn: "http://public@127.0.0.1:" + port + "/42", requestTimeoutMs: 2000,
            beforeSend: function(event, hint) {
                if (scenario == "filtered") return null;
                event.user = null;
                if (event.extra != null) Reflect.deleteField(event.extra, "private");
                if (scenario == "oversize") event.extra.large = StringTools.lpad("", "x", 270000);
                return event;
            }, onError: function(message) flash.Lib.trace(message)};
        if (scenario == "recovery") config.transport = new sentry.transport.HttpTransport();
        Sentry.init(config);
        Sentry.setUser({id: "must-be-redacted"});
        Sentry.setExtra("private", "must-be-redacted");
        Sentry.setContext("game", {room: "square"});
        Sentry.addBreadcrumb({category: "navigation", message: "Entered square"});
        var options:sentry.integrations.FlashHangOptions = {
            thresholdMs: 300, heartbeatIntervalMs: 50, cooldownMs: 0,
            maxRecoveryGapMs: 5000, pauseWhenInactive: false
        };
        if (scenario == "external") { options.externalPort = Std.parseInt(args[2]); options.externalToken = args[3]; }
        monitor = FlashHangMonitor.install(flash.Lib.current.stage, options);
        if (scenario == "launcher") {
            launcher = new AirWatchdogLauncher(config.dsn, args[2], args[3], function(endpoint) {
                options.externalPort = endpoint.externalPort;
                options.externalToken = endpoint.externalToken;
                monitor = FlashHangMonitor.install(flash.Lib.current.stage, options);
                scheduleStall();
            }, function(message) { flash.Lib.trace(message); nativeApp.exit(7); });
        } else scheduleStall();
    }

    static function scheduleStall():Void {
        haxe.Timer.delay(function() {
            if (scenario == "paused") monitor.pause();
            if (scenario == "stopped") monitor.stop();
            checkpoint("armed&mode=" + monitor.mode, function() {
                // External case is suspended by the Node harness with SIGSTOP/SIGCONT.
                if (scenario != "external" && scenario != "launcher") {
                    var until = flash.Lib.getTimer() + 1100;
                    while (flash.Lib.getTimer() < until) {}
                }
                checkpoint("resumed", function() haxe.Timer.delay(finish, 500));
            });
        }, 600);
    }

    static function checkpoint(value:String, then:Void->Void):Void {
        var loader = new flash.net.URLLoader(); loaders.push(loader);
        loader.addEventListener(flash.events.Event.COMPLETE, function(_) { loaders.remove(loader); then(); });
        loader.addEventListener(flash.events.IOErrorEvent.IO_ERROR, function(_) nativeApp.exit(4));
        loader.addEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR, function(_) nativeApp.exit(5));
        loader.load(new flash.net.URLRequest("http://127.0.0.1:" + port + "/checkpoint?scenario=" + scenario + "&state=" + value));
    }

    static function finish():Void {
        if (finished) return;
        finished = true;
        monitor.stop();
        Sentry.close(function(_) {
            // close must not complete while an isolated SDK worker is still running.
            if (flash.system.WorkerDomain.current.listWorkers().length > 1) { nativeApp.exit(6); return; }
            nativeApp.exit(0);
        });
    }
}
