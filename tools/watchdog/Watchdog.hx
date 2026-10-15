import sentry.internal.hang.*;

/** Separate process: Node 18+, no npm dependencies. Emits launcher handshake on stdout. */
class Watchdog {
    static var process:Dynamic = js.Syntax.code("process");
    static var server:Dynamic;
    static var sockets:Array<Dynamic> = [];
    static var backend:sentry.backend.EnvelopeBackend;
    static var timer:haxe.Timer;
    static var startup:haxe.Timer;
    static var observer:HangObserver;
    static var settings:HangSettings;
    static var lastSignal:HangSignal;
    static var disconnectedAt:Null<Float>;
    static var stopping = false;
    static var authenticated = false;
    static var journal:HangJournal;
    static var parentPid = 0;

    static function main():Void {
        try run() catch (error:Dynamic) {
            process.stderr.write("sentry-watchdog: " + Std.string(error) + "\n");
            shutdown(1);
        }
    }

    static function run():Void {
        var args:Array<String> = process.argv.slice(2);
        var dsn:String = process.env.SENTRY_DSN;
        var output:Null<String> = null;
        var port = 0;
        var noSend = false;
        var cacheDirectory:String = null;
        while (args.length > 0) switch (args.shift()) {
            case "--dsn": dsn = required(args);
            case "--port":
                var value = required(args);
                if (!~/^\d+$/.match(value)) throw "Invalid port";
                port = Std.parseInt(value);
                if (port != 0 && (port < 1024 || port > 65535)) throw "Port must be 0 or 1024..65535";
            case "--output-dir": output = required(args);
            case "--cache-dir": cacheDirectory = required(args);
            case "--watch-parent": parentPid = process.ppid;
            case "--parent-pid":
                var value = required(args);
                if (!~/^[0-9]+$/.match(value)) throw "Invalid parent PID";
                var parsed = Std.parseInt(value);
                if (parsed == null || parsed <= 1) throw "Invalid parent PID";
                parentPid = parsed;
            case "--no-send": noSend = true;
            case "--help":
                process.stdout.write("node sentry-watchdog.cjs --dsn <public-dsn> [--port 0] [--cache-dir <directory>] [--watch-parent | --parent-pid <pid>] [--output-dir <directory>] [--no-send]\n");
                return;
            case _: throw "Unknown option; use --help";
        }
        if (dsn == null || StringTools.trim(dsn) == "") throw "Provide --dsn or SENTRY_DSN";
        if (noSend && output == null) throw "--no-send requires --output-dir";
        var config = new sentry.internal.Config({dsn: dsn, maxQueueSize: 34, requestTimeoutMs: 10000,
            onError: function(message) process.stderr.write("sentry-watchdog: " + message + "\n")});
        if (cacheDirectory != null) journal = new HangJournal(cacheDirectory, config.dsn.publicDsn, parentPid, config.report);
        backend = new sentry.backend.EnvelopeBackend(config, new NodeTransport(output, noSend,
            function(id, status) { if (journal != null) journal.delivered(id, status); }));
        if (journal != null) for (event in journal.recover()) backend.capture(event, []);
        var crypto:Dynamic = js.Syntax.code("require('node:crypto')");
        var token:String = crypto.randomBytes(32).toString("hex");
        var net:Dynamic = js.Syntax.code("require('node:net')");
        server = net.createServer(function(socket:Dynamic) accept(socket, token));
        server.on("error", function(_) { process.stderr.write("sentry-watchdog: Cannot listen on loopback\n"); shutdown(1); });
        server.listen(port, "127.0.0.1", function() {
            process.stdout.write(haxe.Json.stringify({type: "listening", version: 1, port: server.address().port, token: token}) + "\n");
        });
        // Do not leave orphaned helpers if a launcher never connects.
        startup = haxe.Timer.delay(function() shutdown(0), 60000);
        process.on("SIGTERM", function() shutdown(0, true));
        process.on("SIGINT", function() shutdown(0, true));
    }

    static function required(args:Array<String>):String {
        if (args.length == 0) throw "Missing option value";
        return args.shift();
    }

    static function accept(socket:Dynamic, token:String):Void {
        if (authenticated || sockets.length >= 4 || stopping) { socket.destroy(); return; }
        sockets.push(socket);
        socket.setEncoding("utf8");
        socket.setNoDelay(true);
        var authorized = false;
        var buffer = "";
        var timeout = haxe.Timer.delay(function() { if (!authorized) socket.destroy(); }, 5000);
        socket.on("error", function(_) socket.destroy());
        socket.on("close", function() {
            timeout.stop();
            sockets.remove(socket);
            if (authorized && !stopping) {
                authenticated = false;
                if (lastSignal == null || !lastSignal.active) shutdown(0);
                else disconnectedAt = Date.now().getTime();
            }
        });
        socket.on("data", function(chunk:String) {
            try {
                buffer += chunk;
                // Before authentication use a small bound. Authenticated snapshots are bounded too.
                if (buffer.length > (authorized ? HangSettings.MAX_SNAPSHOT_BYTES * 2 : 4096)) throw "Packet too large";
                var newline:Int;
                while ((newline = buffer.indexOf("\n")) >= 0) {
                    var line = buffer.substr(0, newline);
                    buffer = buffer.substr(newline + 1);
                    if (line.length > HangSettings.MAX_SNAPSHOT_BYTES + 4096) throw "Packet too large";
                    var message:Dynamic = haxe.Json.parse(line);
                    if (!authorized) {
                        if (authenticated || message.type != "hello" || message.version != 1 || message.token != token) throw "Authentication failed";
                        if (message.settings == null) throw "Missing settings";
                        settings = new HangSettings(message.settings, message.settings.sampleRate);
                        if (journal != null) journal.clearPending();
                        observer = new HangObserver(settings);
                        lastSignal = null;
                        disconnectedAt = null;
                        if (timer != null) timer.stop();
                        authenticated = authorized = true;
                        timeout.stop();
                        startup.stop();
                        // Arming requires a heartbeat; the handshake alone cannot create a hang report.
                        startup = haxe.Timer.delay(function() { if (lastSignal == null) shutdown(0); }, 60000);
                        timer = new haxe.Timer(settings.heartbeatIntervalMs);
                        timer.run = poll;
                        socket.write('{"type":"ready","version":1}\n');
                    } else switch (message.type) {
                        case "beat":
                            var signal:HangSignal = message.signal;
                            if (signal == null || !Std.isOfType(signal.sequence, Int) || !Std.isOfType(signal.active, Bool)) throw "Invalid heartbeat";
                            if (signal.event != null && (!Reflect.isObject(signal.event) || signal.event.event_id == null
                                || !~/^[a-fA-F0-9]{32}$/.match(signal.event.event_id))) throw "Invalid snapshot";
                            lastSignal = signal;
                            var now = Date.now().getTime();
                            var recovered = observer.receive(signal, now);
                            if (recovered != null) report(recovered, now);
                            if (journal != null) journal.savePending(observer.pending);
                        case "stop": shutdown(0); return;
                        case _: throw "Unexpected packet";
                    }
                }
            } catch (_:Dynamic) socket.destroy();
        });
    }

    static function poll():Void {
        if (stopping || observer == null) return;
        var now = Date.now().getTime();
        if (parentPid > 1 && !HangJournal.alive(parentPid)) {
            if (journal != null) journal.savePending(observer.pending, true);
            shutdown(0, true); // Report the cached outcome on the next launch, like Cocoa V2.
            return;
        }
        if (disconnectedAt != null) {
            // Loss of IPC is not proof that the main thread is hanging or that the process died.
            if (now - disconnectedAt >= settings.thresholdMs * 2) shutdown(0, true);
            return;
        }
        observer.poll(now); // Detection only stages a local record. Never send an ongoing event.
        if (journal != null) journal.savePending(observer.pending);
    }

    static function report(incident:HangIncident, now:Float):Void {
        var event = journal == null ? HangEvents.materialize(incident, now, incident.recovered == true) : journal.finalize(incident, now);
        var id = backend.capture(event, []);
        if (id != null) process.stdout.write(haxe.Json.stringify({type: "report", eventId: id,
            hangId: incident.id, recovered: incident.recovered == true}) + "\n");
    }

    static function shutdown(code:Int, preservePending = false):Void {
        if (stopping) return;
        stopping = true;
        if (!preservePending && journal != null) journal.clearPending();
        process.exitCode = code;
        if (startup != null) startup.stop();
        if (timer != null) timer.stop();
        if (server != null) server.close();
        for (socket in sockets.copy()) socket.destroy();
        if (backend != null) backend.close(2000, function(_) {});
    }
}
