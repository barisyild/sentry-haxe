import sentry.Sentry;

/** Run with the real @sentry/browser package and an in-memory SDK transport. */
class BrowserTest {
    static function main():Void {
        var events:Array<Dynamic> = [];
        var envelopes:Array<Dynamic> = [];
        var processedHints = 0;
        var automaticHints = 0;
        Sentry.init({dsn: "https://key@example.com/1", release: "browser-test",
            beforeSend: function(event, _) { Reflect.deleteField(event.extra, "private"); return event; }, nativeOptions: {
            defaultIntegrations: false,
            beforeSend: function(event:Dynamic, hint:Dynamic) {
                if (hint.sentryHaxeProcessed == true) processedHints++; else automaticHints++;
                Reflect.deleteField(event.extra, "private");
                return event;
            },
            transport: function(_) return {
                send: function(envelope:Dynamic) {
                    envelopes.push(envelope);
                    for (item in (cast envelope[1]:Array<Dynamic>)) if (item[0].type == "event") events.push(item[1]);
                    return js.lib.Promise.resolve({statusCode: 200});
                },
                flush: function(_) return js.lib.Promise.resolve(true)
            }
        }});
        Sentry.setUser({id: "player"});
        Sentry.setTag("room", "street");
        Sentry.setExtra("private", "remove before send");
        Sentry.addBreadcrumb({message: "entered"});
        var id = Sentry.withScope(function(scope) {
            scope.setTag("room", "temporary");
            scope.addAttachment(sentry.Attachment.text("hello", "test.txt"));
            return Sentry.captureException(new js.lib.Error("boom"));
        });
        Sentry.captureMessage("after");
        sentry.externs.BrowserSdk.captureMessage("automatic");
        Sentry.flush(1000, function(ok) {
            if (!ok || events.length != 3) throw "SDK did not flush three events";
            if (processedHints != 2 || automaticHints != 1) throw "Cannot distinguish prepared events from native browser captures";
            if (events[0].event_id != id || events[0].tags.room != "temporary" || events[1].tags.room != "street") throw "Scope/event ID mismatch";
            if (events[0].breadcrumbs.length != 1 || events[1].breadcrumbs.length != 1) throw "Duplicate breadcrumbs";
            if (events[0].exception.values[0].stacktrace.frames.length == 0) throw "Missing JS error stack";
            if (envelopes[0][1].length != 2 || envelopes[1][1].length != 1) throw "Attachments leaked across scopes";
            if (events[0].user.id != "player") throw "Missing user";
            if (Reflect.hasField(events[0].extra, "private")) throw "SDK reintroduced redacted scope data";
            Sentry.close(function(_) trace("PASS real Sentry browser SDK: events, scopes, stack, attachment and flush"));
        });
    }
}
