package sentry.transport;

/** Event-loop transports for Flash/AIR, browsers and Lime/TeaVM. */
class HttpTransport implements Transport {
    var cancellations:Array<Void->Void> = [];
    public function new() {}

    public function send(request:Request, done:Response->Void):Void {
        var completed = false;
        var cancel:Void->Void = null;
        var timer:haxe.Timer = null;
        function finish(response:Response):Void {
            if (completed) return;
            completed = true;
            cancellations.remove(cancel);
            if (timer != null) timer.stop();
            done(response);
        }
        #if flash
        var loader = new flash.net.URLLoader();
        loader.dataFormat = flash.net.URLLoaderDataFormat.BINARY;
        var status = 0;
        var headers:Map<String, String> = [];
        loader.addEventListener(flash.events.HTTPStatusEvent.HTTP_STATUS, function(e:flash.events.HTTPStatusEvent) status = e.status);
        #if air
        loader.addEventListener("httpResponseStatus", function(e:flash.events.HTTPStatusEvent) {
            status = e.status;
            for (header in e.responseHeaders) headers[header.name] = header.value;
        });
        #end
        loader.addEventListener(flash.events.Event.COMPLETE, function(_) finish({status: status == 0 ? 200 : status, headers: headers}));
        loader.addEventListener(flash.events.IOErrorEvent.IO_ERROR, function(e:flash.events.IOErrorEvent) finish({status: status, headers: headers, error: e.text}));
        loader.addEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR, function(e:flash.events.SecurityErrorEvent) finish({status: status, error: e.text}));
        cancel = function() { try loader.close() catch (_:Dynamic) {} finish({status: 0, error: "Request cancelled"}); };
        var req = new flash.net.URLRequest(request.url);
        req.method = flash.net.URLRequestMethod.POST;
        req.contentType = request.contentType;
        req.data = request.body.getData();
        #elseif (teavm && lime)
        var loader = new lime.net.HTTPRequest<haxe.io.Bytes>();
        loader.method = lime.net.HTTPRequestMethod.POST;
        loader.contentType = request.contentType;
        loader.data = request.body;
        loader.enableResponseHeaders = true;
        loader.timeout = request.timeoutMs;
        function response(?error:String):Response {
            var headers:Map<String, String> = [];
            if (loader.responseHeaders != null) for (h in loader.responseHeaders) headers[h.name] = h.value;
            return {status: loader.responseStatus, headers: headers, error: error};
        }
        cancel = function() { loader.cancel(); finish({status: 0, error: "Request cancelled"}); };
        #elseif js
        var xhr = new js.html.XMLHttpRequest();
        xhr.open("POST", request.url, true);
        xhr.setRequestHeader("Content-Type", request.contentType);
        xhr.timeout = request.timeoutMs;
        xhr.onload = function(_) {
            var headers:Map<String, String> = [];
            for (line in xhr.getAllResponseHeaders().split("\n")) {
                var colon = line.indexOf(":");
                if (colon > 0) headers[StringTools.trim(line.substr(0, colon))] = StringTools.trim(line.substr(colon + 1));
            }
            finish({status: xhr.status, headers: headers});
        };
        xhr.onerror = function(_) finish({status: 0, error: "Network error"});
        xhr.ontimeout = function(_) finish({status: 0, error: "Request timed out"});
        cancel = function() { xhr.abort(); finish({status: 0, error: "Request cancelled"}); };
        #else
        throw new haxe.Exception("Portable transport requires Flash, JS or Lime/TeaVM. Supply Options.transport on other targets.");
        #end
        #if (flash || js || (teavm && lime))
        cancellations.push(cancel);
        if (request.timeoutMs > 0) timer = haxe.Timer.delay(cancel, request.timeoutMs);
        try {
            #if flash
            loader.load(req);
            #elseif (teavm && lime)
            loader.load(request.url).onComplete(function(_) finish(response())).onError(function(error) finish(response(Std.string(error))));
            #elseif js
            xhr.send(new js.lib.Uint8Array(request.body.getData(), 0, request.body.length));
            #end
        } catch (e:Dynamic) finish({status: 0, error: Std.string(e)});
        #end
    }

    public function close():Void { for (cancel in cancellations.copy()) cancel(); }
}
