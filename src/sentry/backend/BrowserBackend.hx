package sentry.backend;

#if js
import sentry.externs.BrowserSdk;
import sentry.internal.Config;
import sentry.internal.Values;

class BrowserBackend implements Backend {
    var previous:Dynamic = {};
    public function new(config:Config) {
        #if (!sentry_node && !sentry_browser_module)
        if (js.Syntax.code("typeof Sentry === 'undefined'"))
            throw new haxe.Exception("Load the official Sentry browser SDK before initializing sentry-haxe");
        #end
        if (!Reflect.isFunction(BrowserSdk.getCurrentScope))
            throw new haxe.Exception("sentry-haxe requires Sentry JavaScript SDK 8 or newer");
        var options = Values.merge(config.options.nativeOptions, {
            dsn: config.dsn.publicDsn,
            release: config.options.release,
            environment: config.options.environment,
            dist: config.options.dist,
            debug: config.options.debug == true,
            maxBreadcrumbs: config.maxBreadcrumbs,
            sampleRate: 1.0
        });
        // Native integrations contain functions and class instances; do not JSON-normalize them.
        if (config.options.nativeOptions != null) for (key in Reflect.fields(config.options.nativeOptions))
            if (!Reflect.hasField(options, key) || ["dsn", "release", "environment", "dist", "debug", "maxBreadcrumbs", "sampleRate"].indexOf(key) < 0)
                Reflect.setField(options, key, Reflect.field(config.options.nativeOptions, key));
        BrowserSdk.init(options);
    }

    public function capture(event:sentry.Event, attachments:Array<sentry.Attachment>):Null<String> {
        if (event.platform == "other") event.platform = "javascript";
        var result:String = null;
        BrowserSdk.withScope(function(scope) {
            // The event already contains the Haxe scope; avoid attaching it a second time.
            scope.clear();
            for (a in attachments) scope.addAttachment({filename: a.filename, contentType: a.contentType, data: new js.lib.Uint8Array(a.bytes.getData(), 0, a.bytes.length)});
            result = BrowserSdk.captureEvent(event, {event_id: event.event_id, sentryHaxeProcessed: true});
        });
        return result;
    }

    public function syncScope(scope:sentry.Scope):Void {
        var data:Dynamic = scope.snapshot();
        var native = BrowserSdk.getCurrentScope();
        native.setUser(data.user);
        for (group in ["tags", "extra", "contexts"]) {
            var old = Reflect.field(previous, group);
            var current = Reflect.field(data, group);
            if (old != null) for (key in Reflect.fields(old)) if (current == null || !Reflect.hasField(current, key)) {
                switch group {
                    case "tags": native.removeTag(key);
                    case "extra": native.setExtra(key, js.Syntax.code("undefined"));
                    case _: native.setContext(key, null);
                }
            }
            if (current != null) for (key in Reflect.fields(current)) {
                var value = Reflect.field(current, key);
                switch group {
                    case "tags": native.setTag(key, value);
                    case "extra": native.setExtra(key, value);
                    case _: native.setContext(key, value);
                }
            }
        }
        native.setLevel(data.level);
        native.setFingerprint(data.fingerprint);
        native.setTransactionName(data.transaction);
        native.clearBreadcrumbs();
        if (data.breadcrumbs != null) for (b in (cast data.breadcrumbs:Array<Dynamic>)) native.addBreadcrumb(b);
        previous = data;
    }

    public function flush(timeoutMs:Int, done:Bool->Void):Void { BrowserSdk.flush(timeoutMs).then(function(ok) { done(ok); return null; }, function(_) { done(false); return null; }); }
    public function close(timeoutMs:Int, done:Bool->Void):Void { BrowserSdk.close(timeoutMs).then(function(ok) { done(ok); return null; }, function(_) { done(false); return null; }); }
}
#end
