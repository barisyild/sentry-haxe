package sentry.transport;

interface Transport {
    /** Must invoke done once. Responses include non-2xx status codes. */
    public function send(request:Request, done:Response->Void):Void;
    public function close():Void;
}
