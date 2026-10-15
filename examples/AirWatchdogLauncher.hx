#if flash
/** Keep this instance alive in your AIR desktop launcher. Requires extendedDesktop.
    Package a Node runtime and build/sentry-watchdog.cjs; pass their absolute paths.
    Initialize Sentry/Worker monitoring first; replace the monitor when ready fires. */
class AirWatchdogLauncher {
    var process:Dynamic;
    var buffer = "";
    var ready = false;
    var failed = false;
    var timeout:haxe.Timer;
    final onReady:sentry.integrations.FlashHangOptions->Void;
    final onError:String->Void;

    public function new(dsn:String, nodeExecutable:String, watchdogScript:String,
        onReady:sentry.integrations.FlashHangOptions->Void, onError:String->Void) {
        this.onReady = onReady; this.onError = onError;
        try {
            var domain = flash.system.ApplicationDomain.currentDomain;
            if (!domain.hasDefinition("flash.desktop.NativeProcess")) throw "AIR NativeProcess is unavailable";
            var processType:Dynamic = domain.getDefinition("flash.desktop.NativeProcess");
            if (!processType.isSupported) throw "External watchdog requires AIR extendedDesktop";
            var fileType:Class<Dynamic> = cast domain.getDefinition("flash.filesystem.File");
            var info:Dynamic = Type.createInstance(cast domain.getDefinition("flash.desktop.NativeProcessStartupInfo"), []);
            info.executable = Type.createInstance(fileType, [nodeExecutable]);
            var storage:Dynamic = Reflect.field(fileType, "applicationStorageDirectory");
            var cache:Dynamic = storage.resolvePath("sentry-haxe/hangs");
            info.arguments = flash.Vector.ofArray([watchdogScript, "--dsn", new sentry.internal.Dsn(dsn).publicDsn,
                "--cache-dir", cache.nativePath, "--watch-parent"]);
            process = Type.createInstance(cast processType, []);
            process.addEventListener("standardOutputData", stdout);
            process.addEventListener("standardErrorData", stderr);
            process.addEventListener("exit", exited);
            timeout = haxe.Timer.delay(function() fail("Watchdog startup timed out"), 15000);
            process.start(info);
        } catch (error:Dynamic) fail(Std.string(error));
    }

    function stdout(_:Dynamic):Void {
        try {
            buffer += process.standardOutput.readUTFBytes(process.standardOutput.bytesAvailable);
            if (buffer.length > 65536) { fail("Invalid watchdog output"); return; }
            var newline:Int;
            while ((newline = buffer.indexOf("\n")) >= 0) {
                var line = buffer.substr(0, newline); buffer = buffer.substr(newline + 1);
                var message:Dynamic = haxe.Json.parse(line);
                if (!ready && message.type == "listening" && message.version == 1) {
                    if (!Std.isOfType(message.port, Int) || message.port < 1024 || message.port > 65535
                        || !Std.isOfType(message.token, String) || !~/^[a-f0-9]{64}$/.match(message.token)) throw "Invalid watchdog endpoint";
                    ready = true;
                    timeout.stop();
                    onReady({externalPort: message.port, externalToken: message.token});
                }
            }
        } catch (error:Dynamic) fail("Watchdog startup failed: " + Std.string(error));
    }

    function stderr(_:Dynamic):Void {
        // Drain the pipe even after startup so reporting can never block on a full pipe.
        var text:String = process.standardError.readUTFBytes(process.standardError.bytesAvailable);
        onError(text.substr(0, 1024));
    }
    function exited(event:Dynamic):Void {
        if (timeout != null) timeout.stop();
        if (!failed && (!ready || event.exitCode != 0)) onError("External watchdog exited; monitor will use recovery mode");
    }
    function fail(message:String):Void {
        if (failed) return;
        failed = true;
        if (timeout != null) timeout.stop();
        if (process != null) try { if (process.running) process.exit(true); } catch (_:Dynamic) {}
        onError(message);
    }
}
#end
