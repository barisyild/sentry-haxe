package sentry.backend;

interface Backend {
    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String>;
    public function syncScope(scope:sentry.Scope):Void;
    public function flush(timeoutMs:Int, done:Bool->Void):Void;
    public function close(timeoutMs:Int, done:Bool->Void):Void;
}
