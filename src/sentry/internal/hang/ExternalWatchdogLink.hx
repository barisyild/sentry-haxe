package sentry.internal.hang;

#if flash
/** Main-thread IPC. The watchdog must live in a separate OS process. */
class ExternalWatchdogLink {
    public var ready(default, null) = false;
    final port:Int;
    final token:String;
    final settings:HangSettings;
    final report:String->Void;
    var socket:flash.net.Socket;
    var buffer = "";
    var retryAt:Float = 0;
    var connecting = false;
    var stopped = false;
    var warned = false;

    public function new(port:Int, token:String, settings:HangSettings, report:String->Void) {
        if (port < 1024 || port > 65535 || token == null || !~/^[a-fA-F0-9]{32,128}$/.match(token))
            throw new haxe.Exception("External watchdog requires a port >= 1024 and a random hexadecimal token");
        this.port = port; this.token = token; this.settings = settings; this.report = report;
    }

    public function beat(signal:HangSignal, now:Float):Void {
        if (stopped) return;
        if (!ready) {
            if (!connecting && now >= retryAt) connect(now);
            // Includes authentication, not just the TCP connection.
            else if (connecting && now >= retryAt) fail("Watchdog handshake timed out");
            return;
        }
        send({type: "beat", signal: signal});
    }

    function connect(now:Float):Void {
        connecting = true;
        retryAt = now + 5000;
        buffer = "";
        socket = new flash.net.Socket();
        socket.timeout = 3000;
        socket.addEventListener(flash.events.Event.CONNECT, connected);
        socket.addEventListener(flash.events.ProgressEvent.SOCKET_DATA, received);
        socket.addEventListener(flash.events.Event.CLOSE, disconnected);
        socket.addEventListener(flash.events.IOErrorEvent.IO_ERROR, failed);
        socket.addEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR, failed);
        try socket.connect("127.0.0.1", port) catch (_:Dynamic) fail("Cannot connect to external watchdog");
    }

    function connected(_:flash.events.Event):Void {
        send({type: "hello", version: 1, token: token, settings: settings.serialize()});
    }

    function received(_:flash.events.ProgressEvent):Void {
        try {
            buffer += socket.readUTFBytes(socket.bytesAvailable);
            if (buffer.length > 4096) { fail("Invalid watchdog reply"); return; }
            var newline = buffer.indexOf("\n");
            if (newline < 0) return;
            var reply:Dynamic = haxe.Json.parse(buffer.substr(0, newline));
            if (reply.type != "ready" || reply.version != 1) { fail("Watchdog protocol mismatch"); return; }
            buffer = "";
            ready = true;
            connecting = false;
            warned = false;
        } catch (_:Dynamic) fail("Invalid watchdog reply");
    }

    function send(value:Dynamic):Void {
        try {
            if (socket.bytesPending > HangSettings.MAX_SNAPSHOT_BYTES * 2) { fail("Watchdog is not reading heartbeats"); return; }
            socket.writeUTFBytes(sentry.internal.ProtocolJson.stringify(value) + "\n");
            socket.flush();
        } catch (_:Dynamic) fail("Watchdog heartbeat failed");
    }

    function disconnected(_:flash.events.Event):Void fail("External watchdog disconnected");
    function failed(_:flash.events.Event):Void fail("External watchdog socket failed");
    function fail(message:String):Void {
        disconnect();
        retryAt = Date.now().getTime() + 5000;
        if (!warned && !stopped) { warned = true; report(message + "; using recovery detection until reconnect"); }
    }
    function disconnect():Void {
        ready = false;
        connecting = false;
        if (socket == null) return;
        socket.removeEventListener(flash.events.Event.CONNECT, connected);
        socket.removeEventListener(flash.events.ProgressEvent.SOCKET_DATA, received);
        socket.removeEventListener(flash.events.Event.CLOSE, disconnected);
        socket.removeEventListener(flash.events.IOErrorEvent.IO_ERROR, failed);
        socket.removeEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR, failed);
        try socket.close() catch (_:Dynamic) {}
        socket = null;
    }
    public function stop():Void {
        if (stopped) return;
        stopped = true;
        if (ready) send({type: "stop"});
        disconnect();
    }
}
#end
