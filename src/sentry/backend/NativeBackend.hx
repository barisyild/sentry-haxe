package sentry.backend;

#if (cpp && !android && !ios && !sentry_cocoa && !sentry_portable)
import sentry.externs.NativeSdk;
import sentry.internal.Config;

class NativeBackend implements Backend {
    var previous:Dynamic = {};
    public function new(config:Config) {
        var o = NativeSdk.optionsNew();
        NativeSdk.configure(o);
        NativeSdk.setDsn(o, config.dsn.publicDsn);
        if (config.options.release != null) NativeSdk.setRelease(o, Std.string(config.options.release));
        if (config.options.environment != null) NativeSdk.setEnvironment(o, Std.string(config.options.environment));
        if (config.options.dist != null) NativeSdk.setDist(o, Std.string(config.options.dist));
        if (config.options.databasePath != null) NativeSdk.setDatabasePath(o, Std.string(config.options.databasePath));
        if (config.options.handlerPath != null) NativeSdk.setHandlerPath(o, Std.string(config.options.handlerPath));
        NativeSdk.setMaxBreadcrumbs(o, config.maxBreadcrumbs);
        NativeSdk.setDebug(o, config.options.debug == true ? 1 : 0);
        NativeSdk.setShutdownTimeout(o, config.shutdownTimeoutMs);
        if (NativeSdk.init(o) != 0) throw new haxe.Exception("sentry-native initialization failed");
    }

    public static function value(v:Dynamic):cpp.Struct<NativeValue> {
        if (v == null) return NativeSdk.nullValue();
        if (Std.isOfType(v, String)) return NativeSdk.stringValue(Std.string(v));
        if (Std.isOfType(v, Bool)) return NativeSdk.boolValue(v ? 1 : 0);
        if (Std.isOfType(v, Int)) return NativeSdk.intValue(v);
        if (Std.isOfType(v, Float)) return NativeSdk.doubleValue(v);
        if (Std.isOfType(v, Array)) {
            var result = NativeSdk.listValue();
            for (item in (cast v:Array<Dynamic>)) NativeSdk.append(result, value(item));
            return result;
        }
        var result = NativeSdk.objectValue();
        for (key in Reflect.fields(v)) NativeSdk.setKey(result, key, value(Reflect.field(v, key)));
        return result;
    }

    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String> {
        var processed:Dynamic = {};
        for (key in ["user", "tags", "extra", "contexts", "breadcrumbs", "fingerprint", "level", "environment", "transaction"])
            Reflect.setField(processed, key, Reflect.field(event, key));
        processed.context_keys = event.contexts == null ? [] : Reflect.fields(event.contexts);
        var oldContexts = previous == null ? null : Reflect.field(previous, "contexts");
        processed.managed_context_keys = oldContexts == null ? [] : Reflect.fields(oldContexts);
        Reflect.setField(event, "_sentry_haxe_processed", processed);
        var scope = NativeSdk.newScope();
        for (a in attachments) {
            var data:cpp.ConstCharStar = untyped __cpp__("reinterpret_cast<const char*>({0}->b->GetBase())", a.bytes);
            var attachment = NativeSdk.attach(scope, data, a.bytes.length, a.filename);
            NativeSdk.attachmentContentType(attachment, a.contentType);
        }
        var id = NativeSdk.captureEvent(value(event), scope);
        return untyped __cpp__("([](sentry_uuid_t id) -> ::String { if (sentry_uuid_is_nil(&id)) return null(); char text[37], compact[33]; sentry_uuid_as_string(&id, text); int j = 0; for (int i = 0; i < 36; ++i) if (text[i] != '-') compact[j++] = text[i]; compact[32] = 0; return ::String(compact); })({0})", id);
    }

    public function syncScope(scope:sentry.Scope):Void {
        var data:Dynamic = scope.snapshot();
        if (data.user == null) NativeSdk.removeUser(); else NativeSdk.setUser(value(data.user));
        for (group in ["tags", "extra", "contexts"]) {
            var old = Reflect.field(previous, group);
            var current = Reflect.field(data, group);
            if (old != null) for (key in Reflect.fields(old)) if (current == null || !Reflect.hasField(current, key)) {
                switch group { case "tags": NativeSdk.removeTag(key); case "extra": NativeSdk.removeExtra(key); case _: NativeSdk.removeContext(key); }
            }
            if (current != null) for (key in Reflect.fields(current)) {
                var v = Reflect.field(current, key);
                switch group { case "tags": NativeSdk.setTag(key, Std.string(v)); case "extra": NativeSdk.setExtra(key, value(v)); case _: NativeSdk.setContext(key, value(v)); }
            }
        }
        previous = data;
    }

    public function flush(timeoutMs:Int, done:Bool->Void):Void done(NativeSdk.flush(timeoutMs) == 0);
    public function close(timeoutMs:Int, done:Bool->Void):Void { var ok = NativeSdk.flush(timeoutMs) == 0; NativeSdk.close(); done(ok); }
}
#end
