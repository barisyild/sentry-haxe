import sentry.*;
import sentry.backend.*;

class NativeRecorder implements Backend implements NativeScope {
    public var calls:Array<String> = [];
    public var events:Array<Dynamic> = [];
    public var tags:Dynamic = {};
    public function new() {}
    public function count(name:String):Int return calls.filter(c -> c == name).length;
    public function capture(event:Event, attachments:Array<Attachment>):Null<String> { events.push(event); return event.event_id; }
    public function syncScope(scope:Scope):Void calls.push("syncScope");
    public function flush(timeoutMs:Int, done:Bool->Void):Void done(true);
    public function close(timeoutMs:Int, done:Bool->Void):Void done(true);
    public function addBreadcrumb(breadcrumb:Breadcrumb):Void calls.push("addBreadcrumb");
    public function clearBreadcrumbs():Void calls.push("clearBreadcrumbs");
    public function setTag(key:String, value:String):Void { calls.push("setTag"); Reflect.setField(tags, key, value); }
    public function removeTag(key:String):Void { calls.push("removeTag"); Reflect.deleteField(tags, key); }
    public function setExtra(key:String, value:Dynamic):Void calls.push("setExtra");
    public function removeExtra(key:String):Void calls.push("removeExtra");
    public function setContext(key:String, value:Dynamic):Void calls.push("setContext");
    public function removeContext(key:String):Void calls.push("removeContext");
    public function setUser(user:Null<User>):Void calls.push("setUser");
    public function setLevel(level:Null<Level>):Void calls.push("setLevel");
    public function setEnvironment(environment:Null<String>):Void calls.push("setEnvironment");
    public function setFingerprint(fingerprint:Null<Array<String>>):Void calls.push("setFingerprint");
    public function clear():Void calls.push("clear");
}
