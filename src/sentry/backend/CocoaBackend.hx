package sentry.backend;

#if (cpp && (ios || sentry_cocoa) && !android && !sentry_portable)
import sentry.externs.CocoaSdk;
import sentry.internal.ProtocolJson;

class CocoaBackend implements Backend implements NativeScope {
    public function new(config:sentry.internal.Config) CocoaSdk.init(BridgeData.options(config));
    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String> {
        var id = CocoaSdk.capture(ProtocolJson.stringify(event), BridgeData.attachments(attachments));
        return id == "00000000000000000000000000000000" ? null : id;
    }
    public function syncScope(scope:sentry.Scope):Void {}
    public function addBreadcrumb(breadcrumb:sentry.Breadcrumb):Void CocoaSdk.addBreadcrumb(ProtocolJson.stringify(breadcrumb));
    public function clearBreadcrumbs():Void CocoaSdk.clearBreadcrumbs();
    public function setTag(key:String, value:String):Void { if (value == null) CocoaSdk.removeTag(key); else CocoaSdk.setTag(key, value); }
    public function removeTag(key:String):Void CocoaSdk.removeTag(key);
    public function setExtra(key:String, value:Dynamic):Void CocoaSdk.setExtra(key, ProtocolJson.stringify(value));
    public function removeExtra(key:String):Void CocoaSdk.removeExtra(key);
    public function setContext(key:String, value:Dynamic):Void CocoaSdk.setContext(key, ProtocolJson.stringify(value));
    public function removeContext(key:String):Void CocoaSdk.removeContext(key);
    public function setUser(user:Null<sentry.User>):Void CocoaSdk.setUser(ProtocolJson.stringify(user));
    public function setLevel(level:Null<sentry.Level>):Void CocoaSdk.setLevel(ProtocolJson.stringify(level));
    public function setEnvironment(environment:Null<String>):Void CocoaSdk.setEnvironment(ProtocolJson.stringify(environment));
    public function setFingerprint(fingerprint:Null<Array<String>>):Void CocoaSdk.setFingerprint(ProtocolJson.stringify(fingerprint));
    public function clear():Void CocoaSdk.clearScope();
    public function flush(timeoutMs:Int, done:Bool->Void):Void done(CocoaSdk.flush(timeoutMs));
    public function close(timeoutMs:Int, done:Bool->Void):Void done(CocoaSdk.close(timeoutMs));
}
#end
