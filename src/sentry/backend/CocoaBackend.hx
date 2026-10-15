package sentry.backend;

#if (cpp && (ios || sentry_cocoa) && !android && !sentry_portable)
import sentry.externs.CocoaSdk;

class CocoaBackend implements Backend {
    public function new(config:sentry.internal.Config) CocoaSdk.init(BridgeData.options(config));
    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String> {
        var id = CocoaSdk.capture(sentry.internal.ProtocolJson.stringify(event), BridgeData.attachments(attachments));
        return id == "00000000000000000000000000000000" ? null : id;
    }
    public function syncScope(scope:sentry.Scope):Void CocoaSdk.syncScope(sentry.internal.ProtocolJson.stringify(scope.snapshot()));
    public function flush(timeoutMs:Int, done:Bool->Void):Void done(CocoaSdk.flush(timeoutMs));
    public function close(timeoutMs:Int, done:Bool->Void):Void done(CocoaSdk.close(timeoutMs));
}
#end
