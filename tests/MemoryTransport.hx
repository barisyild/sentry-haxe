import sentry.transport.*;

class MemoryTransport implements Transport {
    public var requests:Array<Request> = [];
    public var callbacks:Array<Response->Void> = [];
    public var immediate = true;
    public var response:Response = {status: 200};
    public var closed = false;
    public function new() {}
    public function send(request:Request, done:Response->Void):Void {
        requests.push(request);
        if (immediate) done(response); else callbacks.push(done);
    }
    public function respond(response:Response):Void callbacks.shift()(response);
    public function close():Void { closed = true; }
    public function event(index = 0):Dynamic return haxe.Json.parse(requests[index].body.toString().split("\n")[2]);
}
