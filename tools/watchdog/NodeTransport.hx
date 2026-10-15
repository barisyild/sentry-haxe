import sentry.transport.*;

/** Node-only HTTP transport for the external watchdog, never linked into the game. */
class NodeTransport implements Transport {
    var pending:Array<Dynamic> = [];
    final outputDirectory:Null<String>;
    final noSend:Bool;
    final settled:(String, Int)->Void;

    public function new(outputDirectory:Null<String>, noSend:Bool, ?settled:(String, Int)->Void) {
        this.outputDirectory = outputDirectory;
        this.noSend = noSend;
        this.settled = settled;
        if (outputDirectory != null) {
            var fs:Dynamic = js.Syntax.code("require('node:fs')");
            fs.mkdirSync(outputDirectory, {recursive: true, mode: 448});
        }
    }

    public function send(request:Request, done:Response->Void):Void {
        var bytes = new js.lib.Uint8Array(request.body.getData(), 0, request.body.length);
        var header:Dynamic = haxe.Json.parse(request.body.toString().split("\n")[0]);
        if (outputDirectory != null) {
            var fs:Dynamic = js.Syntax.code("require('node:fs')");
            var path:Dynamic = js.Syntax.code("require('node:path')");
            fs.writeFileSync(path.join(outputDirectory, header.event_id + ".envelope"), bytes, {mode: 384});
        }
        if (noSend) { if (settled != null) settled(header.event_id, 200); done({status: 200}); return; }
        var http:Dynamic = StringTools.startsWith(request.url, "https:")
            ? js.Syntax.code("require('node:https')") : js.Syntax.code("require('node:http')");
        var finished = false;
        var outgoing:Dynamic = null;
        function finish(response:Response):Void {
            if (finished) return;
            finished = true;
            pending.remove(outgoing);
            if (settled != null) settled(header.event_id, response.status);
            done(response);
        }
        outgoing = http.request(request.url, {method: "POST", headers: {
            "Content-Type": request.contentType, "Content-Length": request.body.length
        }}, function(response:Dynamic) {
            response.on("error", function(_) finish({status: 0, error: "Response stream failed"}));
            response.on("end", function() {
                var headers:Map<String, String> = [];
                for (key in Reflect.fields(response.headers)) headers[key] = Std.string(Reflect.field(response.headers, key));
                finish({status: response.statusCode, headers: headers});
            });
            response.resume();
        });
        pending.push(outgoing);
        outgoing.on("error", function(_) finish({status: 0, error: "Watchdog HTTP request failed"}));
        outgoing.setTimeout(request.timeoutMs, function() {
            outgoing.destroy();
            finish({status: 0, error: "Watchdog HTTP request timed out"});
        });
        outgoing.end(bytes);
    }

    public function close():Void { for (request in pending.copy()) request.destroy(); }
}
