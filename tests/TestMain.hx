import sentry.*;
import sentry.internal.*;

class TestMain {
    static var assertions = 0;
    static function check(value:Bool, message:String):Void {
        assertions++;
        if (!value) throw new haxe.Exception(message);
    }
    static function equal(expected:Dynamic, actual:Dynamic, message:String):Void check(expected == actual, message + ': expected $expected, got $actual');
    static function throws(fn:Void->Void, message:String):Void {
        var failed = false;
        try fn() catch (_:Dynamic) failed = true;
        check(failed, message);
    }
    static function main():Void {
        dsn(); protocol(); scope(); nativeScope(); hooks(); queue(); rates(); errors(); symbols(); lifecycle();
        trace('PASS $assertions assertions');
    }
    static function dsn():Void {
        var d = new Dsn("https://public:secret@example.com:9000/sentry/team/42");
        equal("https://public@example.com:9000/sentry/team/42", d.publicDsn, "Never send secret key");
        check(d.envelopeUrl.indexOf("/sentry/team/api/42/envelope/") >= 0, "Self-hosted path prefix");
        check(d.envelopeUrl.indexOf("secret") < 0, "Public authentication only");
        equal("https://key@[::1]:9000/1", new Dsn("https://key@[::1]:9000/1").publicDsn, "IPv6");
        for (bad in ["ftp://key@example.com/1", "https://example.com/1", "https://key@example.com/", "https://key@example.com/no", "https://key@example.com/1?x=1"])
            throws(function() new Dsn(bad), "Reject malformed DSN");
    }
    static function protocol():Void {
        var t = new MemoryTransport();
        var c = new Client({dsn: "https://key@example.com/1", transport: t, release: "game@1", environment: "test"});
        var binary = haxe.io.Bytes.alloc(4);
        binary.set(0, 0); binary.set(1, 255); binary.set(2, 10); binary.set(3, 128);
        var id = c.captureMessage("Türkçe 😀", Info, {attachments: [new Attachment(binary, "ü.bin")]});
        check(~/^[a-f0-9]{32}$/.match(id), "Event ID format");
        var bytes = t.requests[0].body;
        var offset = 0;
        function line():String { var start = offset; while (bytes.get(offset) != 10) offset++; return bytes.getString(start, offset++ - start); }
        var header = haxe.Json.parse(line());
        equal(id, header.event_id, "Envelope/event ID consistency");
        var item = haxe.Json.parse(line());
        var event = haxe.Json.parse(bytes.getString(offset, item.length));
        equal("Türkçe 😀", event.message.formatted, "UTF-8 payload length");
        equal("game@1", event.release, "Release");
        offset += item.length + 1;
        var attachment = haxe.Json.parse(line());
        equal(4, attachment.length, "Attachment byte length");
        equal("ü.bin", attachment.filename, "Unicode filename");
        equal(binary.toHex(), bytes.sub(offset, attachment.length).toHex(), "Binary attachment preserved");
        c.close();
    }
    static function scope():Void {
        var t = new MemoryTransport();
        var c = new Client({dsn: "https://key@example.com/1", transport: t, maxBreadcrumbs: 2});
        c.scope.setTag("room", "outside");
        c.scope.setUser({id: "42"});
        var context:Dynamic = {nested: {name: "first"}};
        c.scope.setContext("game", context);
        context.nested.name = "changed";
        c.addBreadcrumb({message: "first"}); c.addBreadcrumb({message: "second"}); c.addBreadcrumb({message: "third"});
        throws(function() c.withScope(function(s) {
            s.setTag("room", "inside");
            s.addAttachment(Attachment.text("details"));
            c.captureMessage("inner");
            throw new haxe.Exception("callback failure");
        }), "Rethrow user callback exception");
        c.captureMessage("outer");
        equal("inside", t.event(0).tags.room, "Local scope");
        equal("outside", t.event(1).tags.room, "Scope restored after exception");
        equal("first", t.event(1).contexts.game.nested.name, "Scope snapshots caller data");
        equal(2, t.event(1).breadcrumbs.length, "Breadcrumb ring buffer");
        equal("second", t.event(1).breadcrumbs[0].message, "Oldest breadcrumb removed");
        equal(0, c.scope.getAttachments().length, "Attachments isolated");
        c.captureEvent({tags: {room: "override"}});
        equal("override", t.event(2).tags.room, "Event wins over scope");
        c.scope.setUser(null); c.scope.removeTag("room");
        c.captureMessage("logout");
        check(t.event(3).user == null && !Reflect.hasField(t.event(3).tags, "room"), "Clear user and tag");
        c.close();
    }
    static function nativeScope():Void {
        var n = new NativeRecorder();
        var c:Client = null;
        c = new Client({dsn: "https://key@example.com/1", transport: new MemoryTransport(), release: "game@1", environment: "test", maxBreadcrumbs: 2,
            beforeSend: function(event, hint) {
                var crumb:Breadcrumb = {category: "exception", message: "stack"};
                c.addBreadcrumb(crumb);
                event.breadcrumbs.push(crumb);
                return event;
            }});
        @:privateAccess c.attach(n);
        check(c.scope.isNative(), "Platform scope owns the global scope");
        c.scope.setTag("room", "outside");
        c.scope.setUser({id: "42"});
        c.scope.setEnvironment("turkey");
        for (i in 0...5) c.addBreadcrumb({message: "b" + i, data: {i: i}});
        equal(5, n.count("addBreadcrumb"), "Each breadcrumb forwarded once");
        equal(0, n.count("clearBreadcrumbs") + n.count("syncScope"), "No scope resync");
        equal(null, c.scope.snapshot().breadcrumbs, "Haxe keeps no breadcrumb copy");
        equal("outside", n.tags.room, "Tag forwarded");
        c.captureMessage("outer");
        equal(1, n.events.length, "Event captured through the platform");
        equal(null, n.events[0].environment, "Platform fills environment");
        equal(null, n.events[0].release, "Platform fills release");
        equal(0, n.events[0].breadcrumbs.length, "beforeSend breadcrumb reaches the event once, through the platform scope");
        equal(6, n.count("addBreadcrumb"), "beforeSend breadcrumb forwarded");
        var tagCalls = n.count("setTag");
        c.withScope(function(s) {
            s.setTag("room", "inside");
            c.captureMessage("inner");
        });
        equal(tagCalls, n.count("setTag"), "Local scope stays out of the platform scope");
        equal("inside", n.events[1].tags.room, "Local scope applied to its event");
        equal(1, n.events[1].breadcrumbs.length, "Local beforeSend breadcrumb kept on its event");
        equal(6, n.count("addBreadcrumb"), "Local breadcrumb not forwarded");
        check(c.scope.isNative(), "Platform scope restored");
        c.scope.setContext("game", {nested: {name: "first"}});
        c.scope.setContext("game", null);
        equal(1, n.count("setContext"), "Context forwarded");
        equal(1, n.count("removeContext"), "Null context removes it");
        c.scope.clear();
        equal(1, n.count("clear"), "Clear forwarded");
        equal(0, n.count("syncScope"), "Platform scope never resynced");
        c.close();
    }
    static function hooks():Void {
        var t = new MemoryTransport();
        var original:Dynamic = null;
        var c = new Client({dsn: "https://key@example.com/1", transport: t,
            beforeSend: function(event, hint) { original = hint.originalException; event.tags.filtered = "yes"; return event; },
            beforeBreadcrumb: function(b) return b.category == "private" ? null : b});
        c.addBreadcrumb({category: "private", message: "password"});
        c.addBreadcrumb({message: "safe"});
        var e = new haxe.Exception("failure");
        c.captureException(e);
        check(original == e, "Hook original exception");
        equal("yes", t.event().tags.filtered, "Hook edits");
        equal(1, t.event().breadcrumbs.length, "Breadcrumb filtering");
        var cycle:Dynamic = {value: 4}; cycle.self = cycle;
        c.scope.setExtra("cycle", cycle); c.captureMessage("cycle");
        equal("[Circular]", t.event(1).extra.cycle.self, "Cycle-safe serialization");
        c.close();
        var dropped = new Client({dsn: "https://key@example.com/1", transport: t, beforeSend: function(_, _) return null});
        equal(null, dropped.captureMessage("drop"), "beforeSend drops event"); dropped.close();
        var sampled = new Client({dsn: "https://key@example.com/1", transport: t, sampleRate: 0});
        equal(null, sampled.captureMessage("drop"), "Sampling zero"); sampled.close();
        throws(function() new Client({sampleRate: 2}), "Reject invalid sampling");
        var disabled = new Client({dsn: ""}); equal(null, disabled.captureMessage("off"), "Empty DSN disables SDK");
        var reports = 0;
        var failure = new Client({dsn: "https://key@example.com/1", transport: t, beforeSend: function(_, _) throw "hook failure", onError: function(_) reports++});
        equal(null, failure.captureMessage("safe"), "Hook failure does not crash game"); equal(1, reports, "Hook failure reported"); failure.close();
        var replacementTransport = new MemoryTransport();
        var replacement = new Client({dsn: "https://key@example.com/1", transport: replacementTransport, beforeSend: function(_, _) return {message: {formatted: "replacement"}}});
        var replacementId = replacement.captureMessage("original");
        check(replacementId != null && replacementId == replacementTransport.event().event_id, "Replacement event retains generated ID");
        replacement.close();
        var small = new Client({dsn: "https://key@example.com/1", transport: t, maxAttachmentBytes: 1});
        equal(null, small.captureMessage("oversized", Info, {attachments: [Attachment.text("too large")]}), "Oversized attachments rejected");
        small.close();
        throws(function() new Scope(-1), "Negative standalone scope breadcrumb limit rejected");
    }
    static function queue():Void {
        var t = new MemoryTransport(); t.immediate = false;
        var c = new Client({dsn: "https://key@example.com/1", transport: t, maxQueueSize: 2, requestTimeoutMs: 0});
        c.captureMessage("1"); c.captureMessage("2");
        equal(null, c.captureMessage("3"), "Bounded pending queue");
        equal(1, t.requests.length, "Single in-flight request");
        var flushed:Null<Bool> = null;
        c.flush(1000, function(ok) flushed = ok);
        equal(null, flushed, "flush waits for pending envelopes");
        t.respond({status: 200}); equal(2, t.requests.length, "Queue drains in order");
        t.respond({status: 200}); equal(true, flushed, "flush reports completion");
        c.close(); check(t.closed, "Transport closed");
        equal(null, c.captureMessage("closed"), "Closed client drops captures");
        var t2 = new MemoryTransport(); t2.immediate = false;
        var c2 = new Client({dsn: "https://key@example.com/1", transport: t2, requestTimeoutMs: 0});
        c2.captureMessage("fail"); c2.flush(1000, function(ok) flushed = ok); t2.respond({status: 500});
        equal(false, flushed, "flush reflects pending delivery failure"); c2.close();
    }
    static function rates():Void {
        var r = new RateLimits();
        r.update({status: 200, headers: ["X-Sentry-Rate-Limits" => "5:error:organization,10:attachment:organization,99:unknown:organization"]}, 100);
        check(r.limited("error", 104), "Error rate limit"); check(!r.limited("error", 106), "Limit expires");
        check(r.limited("attachment", 106), "Independent attachment limit"); check(!r.limited("unknown", 100), "Ignore unknown categories");
        r.update({status: 429, headers: ["Retry-After" => "3"]}, 200);
        check(r.limited("error", 202), "Retry-After"); check(!r.limited("error", 204), "Retry expires");
        var date = new RateLimits(); date.update({status: 429, headers: ["retry-after" => "Thu, 01 Jan 1970 00:02:00 GMT"]}, 100);
        check(date.limited("error", 119) && !date.limited("error", 121), "HTTP-date Retry-After uses UTC");
        var t = new MemoryTransport(); t.immediate = false;
        var c = new Client({dsn: "https://key@example.com/1", transport: t, requestTimeoutMs: 0});
        c.captureMessage("first"); c.captureMessage("queued");
        t.respond({status: 429}); equal(1, t.requests.length, "429 drops queued errors");
        equal(null, c.captureMessage("limited"), "Rate limited captures rejected"); c.close();
    }
    static function errors():Void {
        var t = new MemoryTransport();
        var c = new Client({dsn: "https://key@example.com/1", transport: t});
        var cause = new haxe.Exception("root"); var outer = new haxe.Exception("outer", cause);
        c.captureException(outer, {handled: false});
        var values = t.event().exception.values;
        equal(2, values.length, "Exception chain"); equal("root", values[0].value, "Oldest exception first");
        equal(false, values[1].mechanism.handled, "Unhandled mechanism");
        var frames = Exceptions.stackFrames([FilePos(Method("Game", "newest"), "Game.hx", 10), FilePos(Method("Main", "oldest"), "Main.hx", 2)]);
        equal("Main.hx", frames[0].filename, "Oldest frame first");
        equal(10, frames[1].lineno, "Frame line retained");
        c.close();
    }
    static function lifecycle():Void {
        var t = new MemoryTransport();
        Sentry.init({dsn: "https://key@example.com/1", transport: t});
        throws(function() Sentry.init({dsn: "https://key@example.com/1", transport: t}), "Explicit lifecycle prevents concurrent global SDK instances");
        Sentry.setTag("application", "example-app"); Sentry.captureMessage("ready");
        equal("example-app", t.event().tags.application, "Facade delegates");
        Sentry.close(); check(!Sentry.isEnabled(), "Facade closes");
        var pending = new MemoryTransport(); pending.immediate = false;
        Sentry.init({dsn: "https://key@example.com/1", transport: pending, requestTimeoutMs: 0});
        Sentry.captureMessage("pending");
        var closes = 0;
        Sentry.close(function(_) closes++);
        Sentry.close(function(_) closes++);
        throws(function() Sentry.init({enabled: false}), "Reinit waits for async close");
        pending.respond({status: 200});
        equal(2, closes, "Concurrent close callbacks complete once each");
        Sentry.init({enabled: false});
    }

    static function symbols():Void {
        var frames = Exceptions.parseFlashStack("TypeError: Error #1009\n"
            + "\tat §中§/§한§()[src/Game.hx:23]\n"
            + "\tat example::Main$/start()[C:\\src\\Main.hx:9]\n"
            + "\tat example::Main()\n\tat MethodInfo-42()\n");
        equal(4, frames.length, "Parse AVM2 stack frames");
        equal("§中§", frames[3].module, "Unicode class identifier preserved");
        equal("§한§", Reflect.field(frames[3], "function"), "Separate AVM2 method");
        equal(23, frames[3].lineno, "Actual Flash source line preserved");
        equal("src/Game.hx", frames[3].filename, "Relative Flash source path");
        equal("example.Main", frames[2].module, "Namespace and static class marker");
        equal("C:\\src\\Main.hx", frames[2].filename, "Windows Flash source path");
        equal("new", Reflect.field(frames[1], "function"), "Constructor frame");
        equal(null, frames[0].module, "Anonymous method has no invented class");
        equal(0, Exceptions.parseFlashStack(null).length, "Release player without a stack");
        var uuid = "1a876fc1-6ef9-4b93-9f35-11784da018ef";
        var native:Dynamic = {module: "native", "function": "fn", platform: "native"};
        var event:Event = {platform: "other", exception: {values: [{stacktrace: {frames: frames}}]},
            threads: {values: [{stacktrace: {frames: [native]}}]}, debug_meta: {images: [{type: "macho", debug_id: "original"}]}};
        sentry.integrations.Proguard.apply(event, uuid);
        sentry.integrations.Proguard.apply(event, uuid);
        equal("other", event.platform, "Runtime event platform is unchanged");
        equal("java", frames[3].platform, "Named VM frame selects ProGuard resolver");
        equal("native", native.platform, "Do not override native symbolication");
        equal(null, frames[0].platform, "Do not label anonymous frames as JVM");
        equal(2, event.debug_meta.images.length, "Idempotent UUID metadata preserves other images");
        equal(uuid, event.debug_meta.images[1].uuid, "Mapping UUID");
        var hang:Event = {exception: {values: [{type: "AppHang"}]}};
        sentry.integrations.Proguard.apply(hang, uuid);
        equal(null, hang.debug_meta, "Synthetic hangs do not invent stack frames");
        throws(function() sentry.integrations.Proguard.apply(event, "invalid"), "Reject invalid mapping UUID");
    }
}
