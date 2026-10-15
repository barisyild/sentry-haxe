package sentry.backend;

#if (cpp && android && !sentry_portable)
#if !lime
#error "The Android backend requires Lime for JNI. Use -lib lime and the sentry-haxe include.xml."
#end
import sentry.externs.AndroidSdk;

class AndroidBackend implements Backend {
    public function new(config:sentry.internal.Config) AndroidSdk.init(BridgeData.options(config));
    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String> {
        var id = AndroidSdk.capture(sentry.internal.ProtocolJson.stringify(event), BridgeData.attachments(attachments));
        return id == "00000000000000000000000000000000" ? null : id;
    }
    public function syncScope(scope:sentry.Scope):Void AndroidSdk.syncScope(sentry.internal.ProtocolJson.stringify(scope.snapshot()));
    public function flush(timeoutMs:Int, done:Bool->Void):Void done(AndroidSdk.flush(timeoutMs));
    public function close(timeoutMs:Int, done:Bool->Void):Void done(AndroidSdk.close(timeoutMs));
}
#end
