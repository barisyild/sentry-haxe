package sentry;

import sentry.internal.Config;
import sentry.internal.Values;
import sentry.internal.Exceptions;
import sentry.backend.Backend;

/** A client and its synchronous scope stack belong to one application thread. */
@:allow(sentry.integrations.FlashHangMonitor)
class Client {
    public var scope(default, null):Scope;
    public var enabled(default, null):Bool = false;
    public var closing(default, null):Bool = false;
    public var lastEventId(default, null):Null<String>;
    final config:Config;
    var backend:Backend;
    var processing = false;
    var closeCallbacks:Array<Bool->Void> = [];
    var stopHangMonitor:(Void->Void)->Void;

    public function new(options:Options) {
        config = new Config(options);
        scope = new Scope(config.maxBreadcrumbs, syncScope);
        if (!config.enabled) return;
        backend = sentry.backend.BackendFactory.create(config);
        enabled = true;
    }

    function syncScope():Void {
        if (enabled) try backend.syncScope(scope) catch (e:Dynamic) config.report("Scope sync failed: " + Std.string(e));
    }

    public function withScope<T>(callback:Scope->T):T {
        var previous = scope;
        scope = previous.clone(syncScope);
        try {
            var result = callback(scope);
            scope = previous;
            syncScope();
            return result;
        } catch (error:Dynamic) {
            scope = previous;
            syncScope();
            throw error;
        }
    }

    public function addBreadcrumb(breadcrumb:Breadcrumb):Void {
        if (!enabled || breadcrumb == null) return;
        try {
            var b:Breadcrumb = Values.copy(breadcrumb);
            if (config.options.beforeBreadcrumb != null) b = config.options.beforeBreadcrumb(b);
            if (b != null) scope.addBreadcrumb(b);
        } catch (e:Dynamic) config.report("beforeBreadcrumb failed: " + Std.string(e));
    }

    public function captureMessage(message:String, level:Level = Info, ?hint:Hint):Null<String> {
        return captureEvent({message: {formatted: message}, level: level}, hint);
    }

    public function captureException(error:Dynamic, ?hint:Hint):Null<String> {
        if (hint == null) hint = {};
        hint.originalException = error;
        return captureEvent(Exceptions.event(error, hint.handled != false), hint);
    }

    public function captureEvent(event:Event, ?hint:Hint):Null<String> {
        if (!enabled || processing || event == null || config.sampleRate == 0 || Math.random() >= config.sampleRate) return null;
        processing = true;
        var id:Null<String> = null;
        try {
            if (hint == null) hint = {};
            var e = prepareEvent(event, hint);
            if (e != null) {
                var attachments = scope.getAttachments();
                if (hint.attachments != null) attachments = attachments.concat(hint.attachments);
                var size = 0;
                for (a in attachments) size += a.bytes.length;
                if (size > config.maxAttachmentBytes) throw new haxe.Exception("Attachments exceed maxAttachmentBytes");
                id = backend.capture(Values.copy(e), attachments);
                if (id != null) lastEventId = id;
            }
        } catch (e:Dynamic) config.report("Capture failed: " + Std.string(e));
        processing = false;
        return id;
    }

    function prepareEvent(event:Event, hint:Hint):Null<Event> {
        var e = scope.apply(event);
        if (e.event_id == null) e.event_id = Values.id();
        if (e.timestamp == null) e.timestamp = Values.now();
        if (e.platform == null) e.platform = "other";
        if (e.release == null) e.release = config.options.release;
        if (e.environment == null) e.environment = config.options.environment;
        if (e.dist == null) e.dist = config.options.dist;
        var eventId = e.event_id;
        var timestamp = e.timestamp;
        if (config.options.beforeSend != null) e = config.options.beforeSend(e, hint);
        if (e == null) return null;
        if (e.event_id == null) e.event_id = eventId;
        if (e.timestamp == null) e.timestamp = timestamp;
        if (e.platform == null) e.platform = "other";
        if (!~/^[a-fA-F0-9]{32}$/.match(e.event_id)) throw new haxe.Exception("event_id must contain 32 hexadecimal characters");
        return e;
    }

    function prepareHangSnapshot(event:Event):Null<Event> {
        if (!enabled || processing || config.sampleRate == 0) return null;
        processing = true;
        var snapshot:Null<Event> = null;
        try snapshot = Values.copy(prepareEvent(event, {hangSnapshot: true}))
        catch (error:Dynamic) config.report("Hang snapshot failed: " + Std.string(error));
        processing = false;
        return enabled ? snapshot : null;
    }

    function capturePreparedHang(event:Event):Void {
        if (!enabled) return;
        try {
            var id = backend.capture(event, []);
            if (id != null) lastEventId = id;
        } catch (error:Dynamic) config.report("Hang capture failed: " + Std.string(error));
    }

    public function flush(timeoutMs = 2000, ?done:Bool->Void):Void {
        if (done == null) done = function(_) {};
        if (!enabled && !closing) { done(true); return; }
        backend.flush(Std.int(Math.max(0, timeoutMs)), done);
    }

    public function close(?done:Bool->Void):Void {
        if (done == null) done = function(_) {};
        if (closing) { closeCallbacks.push(done); return; }
        if (!enabled) { done(true); return; }
        enabled = false;
        closing = true;
        closeCallbacks.push(done);
        function finishMonitor():Void {
            backend.close(config.shutdownTimeoutMs, function(ok) {
                closing = false;
                var callbacks = closeCallbacks;
                closeCallbacks = [];
                for (callback in callbacks) callback(ok);
            });
        }
        if (stopHangMonitor != null) stopHangMonitor(finishMonitor); else finishMonitor();
    }
}
