package sentry;

import sentry.internal.Values;
import sentry.backend.NativeScope;

class Scope {
    var data:Event = {};
    var attachments:Array<Attachment> = [];
    var changed:Void->Void;
    var maxBreadcrumbs:Int;
    var native:Null<NativeScope>;

    public function new(maxBreadcrumbs = 100, ?changed:Void->Void, ?native:NativeScope) {
        if (maxBreadcrumbs < 0) throw new haxe.Exception("maxBreadcrumbs must not be negative");
        this.maxBreadcrumbs = maxBreadcrumbs;
        this.changed = changed;
        this.native = native;
    }

    public function isNative():Bool return native != null;
    function notifyChanged():Void { if (changed != null) changed(); }
    public function setTag(key:String, value:String):Void { if (native != null) native.setTag(key, value); else field("tags", key, value); }
    public function removeTag(key:String):Void { if (native != null) native.removeTag(key); else remove("tags", key); }
    public function setExtra(key:String, value:Dynamic):Void { if (native != null) native.setExtra(key, Values.copy(value)); else field("extra", key, value); }
    public function removeExtra(key:String):Void { if (native != null) native.removeExtra(key); else remove("extra", key); }
    public function setContext(key:String, value:Dynamic):Void {
        if (native != null) { if (value == null) native.removeContext(key); else native.setContext(key, Values.copy(value)); }
        else if (value == null) remove("contexts", key); else field("contexts", key, value);
    }
    public function setUser(user:Null<User>):Void { if (native != null) native.setUser(Values.copy(user)); else { data.user = Values.copy(user); notifyChanged(); } }
    public function setLevel(level:Level):Void { if (native != null) native.setLevel(level); else { data.level = level; notifyChanged(); } }
    public function setEnvironment(environment:String):Void { if (native != null) native.setEnvironment(environment); else { data.environment = environment; notifyChanged(); } }
    public function setFingerprint(fingerprint:Array<String>):Void {
        var copy = fingerprint == null ? null : fingerprint.copy();
        if (native != null) native.setFingerprint(copy); else { data.fingerprint = copy; notifyChanged(); }
    }
    public function setTransactionName(name:String):Void { data.transaction = name; notifyChanged(); }
    public function addAttachment(attachment:Attachment):Void { attachments.push(attachment); notifyChanged(); }
    public function clearAttachments():Void { attachments = []; notifyChanged(); }
    public function getAttachments():Array<Attachment> { return attachments.copy(); }
    public function clearBreadcrumbs():Void { if (native != null) native.clearBreadcrumbs(); else { data.breadcrumbs = []; notifyChanged(); } }
    public function clear():Void { if (native != null) native.clear(); data = {}; attachments = []; notifyChanged(); }

    public function addBreadcrumb(breadcrumb:Breadcrumb):Void {
        if (maxBreadcrumbs == 0) return;
        var b:Breadcrumb = Values.copy(breadcrumb);
        if (b.timestamp == null) b.timestamp = Values.now();
        if (native != null) { native.addBreadcrumb(b); return; }
        if (data.breadcrumbs == null) data.breadcrumbs = [];
        data.breadcrumbs.push(b);
        while (data.breadcrumbs.length > maxBreadcrumbs) data.breadcrumbs.shift();
        notifyChanged();
    }

    function field(group:String, key:String, value:Dynamic):Void {
        var obj = Reflect.field(data, group);
        if (obj == null) { obj = {}; Reflect.setField(data, group, obj); }
        Reflect.setField(obj, key, Values.copy(value));
        notifyChanged();
    }

    function remove(group:String, key:String):Void {
        var obj = Reflect.field(data, group);
        if (obj != null) Reflect.deleteField(obj, key);
        notifyChanged();
    }

    public function snapshot():Event return Values.copy(data);

    public function clone(?changed:Void->Void):Scope {
        var scope = new Scope(maxBreadcrumbs, changed);
        scope.data = snapshot();
        scope.attachments = attachments.copy();
        return scope;
    }

    public function apply(event:Event):Event {
        var result:Event = Values.merge(data, event);
        for (key in ["tags", "extra", "contexts"])
            Reflect.setField(result, key, Values.merge(Reflect.field(data, key), Reflect.field(event, key)));
        var crumbs = data.breadcrumbs == null ? [] : data.breadcrumbs.copy();
        if (event.breadcrumbs != null) crumbs = crumbs.concat(event.breadcrumbs);
        result.breadcrumbs = Values.copy(crumbs.slice(Std.int(Math.max(0, crumbs.length - maxBreadcrumbs))));
        return result;
    }
}
