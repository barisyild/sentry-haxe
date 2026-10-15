package sentry.backend;

#if ((java || jvm) && !teavm && !sentry_portable)
import sentry.externs.JavaSdk;

class JavaBackend implements Backend {
    public function new(config:sentry.internal.Config) JavaSdk.init(BridgeData.options(config));
    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String> {
        var id = JavaSdk.capture(sentry.internal.ProtocolJson.stringify(event), BridgeData.attachments(attachments));
        return id == "00000000000000000000000000000000" ? null : id;
    }
    public function syncScope(scope:sentry.Scope):Void JavaSdk.syncScope(sentry.internal.ProtocolJson.stringify(scope.snapshot()));
    public function flush(timeoutMs:Int, done:Bool->Void):Void done(JavaSdk.flush(timeoutMs));
    public function close(timeoutMs:Int, done:Bool->Void):Void done(JavaSdk.close(timeoutMs));
}
#end
