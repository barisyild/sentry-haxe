import sentry.internal.hang.*;
import sentry.internal.Values;

@:access(sentry.Client)
class HangTest {
    static var assertions = 0;
    static function check(value:Bool, label:String):Void { assertions++; if (!value) throw label; }
    static function settings(cooldown = 0, sample = 1.0):HangSettings
        return new HangSettings({thresholdMs: 300, heartbeatIntervalMs: 50, cooldownMs: cooldown, maxRecoveryGapMs: 1000}, sample);
    static function signal(sequence:Int, active = true, ?room:String):HangSignal return {
        sequence: sequence, active: active,
        event: {event_id: Values.id(), timestamp: 1, tags: {room: room == null ? "square" : room}}
    };
    static function advance(observer:HangObserver, from:Int, to:Int):Null<HangIncident> {
        var result = null;
        var now = from;
        while (now <= to) { var event = observer.poll(now); if (event != null) result = event; now += 50; }
        return result;
    }
    static function main():Void {
        observer(); observedRecovery(); recovery(); events(); privacy();
        trace("PASS " + assertions + " hang assertions");
    }
    static function observedRecovery():Void {
        var o = new HangObserver(settings(1000));
        o.receive(signal(0, true, "before"), 0);
        var detected = advance(o, 0, 300);
        check(detected != null && !detected.recovered, "Threshold stages a pending incident");
        advance(o, 350, 700);
        var recovered = o.receive(signal(1, true, "after"), 750);
        check(recovered != null && recovered.recovered && recovered.durationMs == 750, "Recovery carries the full heartbeat gap despite cooldown");
        check(recovered.id == detected.id && recovered.detectedAtMs == 300 && o.pending == null, "Final event retains its staged identity and detection time");
        check(recovered.event.tags.room == "before", "Recovery retains pre-hang context");
        check(o.receive(signal(2), 800) == null, "Recovery is sent only once");
        check(advance(o, 800, 1100) == null, "Another hang inside cooldown stays suppressed");
        check(o.receive(signal(3), 1150) == null, "Suppressed hang cannot leak a recovery event");
        var longHang = advance(o, 1150, 2500);
        var longRecovery = o.receive(signal(4), 2550);
        check(longHang != null && longRecovery != null && longRecovery.durationMs == 1400,
            "Continuously watched hangs can recover beyond the recovery-only maximum");

        var beforePoll = new HangObserver(settings());
        beforePoll.receive(signal(0), 0);
        advance(beforePoll, 0, 250);
        var justRecovered = beforePoll.receive(signal(1), 310);
        check(justRecovered != null && justRecovered.recovered && justRecovered.detectedAtMs == 310,
            "Recovery just before threshold poll emits one standalone event");
        check(beforePoll.poll(310) == null, "No duplicate threshold event after recovery");

        var sampled = new HangObserver(settings(0, 0));
        sampled.receive(signal(0), 0);
        advance(sampled, 0, 400);
        check(sampled.receive(signal(1), 450) == null, "Sampled-out episode has no recovery");
        for (mode in ["paused", "revoked", "sleep", "backward"]) {
            var suppressed = new HangObserver(settings());
            suppressed.receive(signal(0), 0); advance(suppressed, 0, 300);
            var next = signal(1, mode != "paused");
            if (mode == "revoked") next.event = null;
            var now = mode == "sleep" ? 10000 : mode == "backward" ? -100 : 350;
            check(suppressed.receive(next, now) == null, "No false recovery after " + mode);
        }
        var asleep = new HangObserver(settings());
        asleep.receive(signal(0), 0); advance(asleep, 0, 300);
        check(asleep.poll(10000) == null, "Observer sleep cancels pending duration");
        check(asleep.receive(signal(1), 10050) == null, "Wake-up does not claim ten-second app recovery");
    }
    static function observer():Void {
        var o = new HangObserver(settings());
        check(advance(o, 0, 1000) == null, "No heartbeat means unarmed");
        o.receive(signal(0), 1000);
        check(advance(o, 1050, 1250) == null, "Threshold not reached");
        var first = o.poll(1300);
        check(first != null && first.durationMs == 300, "Independent observer detects the stall");
        check(advance(o, 1350, 2000) == null, "Only one report per continuous hang");
        o.receive(signal(0), 2000);
        check(advance(o, 2050, 2350) == null, "Repeated sequence cannot rearm or hide a stall");
        o.receive(signal(1), 2400);
        check(advance(o, 2400, 2700) != null, "Fresh heartbeat rearms");
        o.receive(signal(2, false), 2800);
        check(advance(o, 2800, 4000) == null, "Inactive application never reports");
        var revoked = signal(3); revoked.event = null;
        o.receive(revoked, 4100);
        check(advance(o, 4100, 4500) == null, "Null snapshot revokes previous user data");

        var healthy = new HangObserver(settings());
        for (i in 0...20) { healthy.receive(signal(i), i * 50); check(healthy.poll(i * 50) == null, "Healthy heartbeat " + i); }
        var limited = new HangObserver(settings(1000));
        limited.receive(signal(0), 0); check(advance(limited, 0, 300) != null, "First report before cooldown");
        limited.receive(signal(1), 350); check(advance(limited, 350, 1500) == null, "Cooldown does not turn the same hang into a later duplicate");
        limited.receive(signal(2), 1550); check(advance(limited, 1550, 1850) != null, "New hang after cooldown");
        var sampled = new HangObserver(settings(0, 0));
        sampled.receive(signal(0), 0); check(advance(sampled, 0, 500) == null, "Sampling zero");

        var sleep = new HangObserver(settings());
        sleep.receive(signal(0), 0); sleep.poll(0);
        check(sleep.poll(10000) == null, "Sleeping observer does not blame main thread");
        check(advance(sleep, 10050, 10250) == null, "Resume grace period");
        check(sleep.poll(10300) != null, "Persistent hang detectable after observer resumes");
        sleep.receive(signal(1), 10350);
        check(sleep.poll(-100) == null, "Backward wall clock resets observation");
    }
    static function recovery():Void {
        var r = new HangRecovery(settings());
        check(r.beat(signal(0, true, "before"), 0) == null, "First recovery pulse arms");
        var event = r.beat(signal(1, true, "after"), 300);
        check(event != null && event.event.tags.room == "before", "Recovered hang uses last pre-hang context");
        check(r.beat(signal(2), 350) == null, "Normal callback is not a recovered hang");
        check(r.beat(signal(3), 10000) == null, "Very long recovery-only gap suppressed as possible sleep");
        r.beat(signal(4, false), 10100);
        check(r.beat(signal(5), 10500) == null, "Paused time excluded");
        r.reset();
        check(r.beat(signal(6), 11000) == null, "Explicit resume does not report paused gap");
        var revoked = signal(7); revoked.event = null;
        check(r.beat(revoked, 11350) == null, "Recovery-only mode respects current snapshot revocation");
    }
    static function events():Void {
        var template = HangEvents.template("worker", 300);
        template.timestamp = 1;
        var event = HangEvents.materialize({event: template, durationMs: 300}, 1400, false);
        check(event.contexts.app_hang.duration_ms == 300, "Duration in context");
        check(event.contexts.app_hang.snapshot_age_ms == 400, "Snapshot age in context");
        check(event.contexts.app_hang.recovered == false, "Frozen main thread marker");
        check(event.exception.values[0].stacktrace == null, "Does not invent a frozen stack trace");
        check(event.event_id.length == 32 && event.timestamp == 1.4, "Fresh report ID and timestamp");
        check(template.contexts.app_hang.duration_ms == 0, "Snapshot remains immutable");
        check(HangEvents.materialize({event: template, durationMs: 300}, 1400, true).contexts.app_hang.recovered, "Recovered marker");
        var id = Values.id();
        var recovered = HangEvents.materialize({event: template, durationMs: 6500, id: id, detectedAtMs: 1300,
            durationMinMs: 6400, durationMaxMs: 6500, endReason: "heartbeat_resumed"}, 7500, true);
        check(recovered.event_id == id && recovered.timestamp == 1.3, "One event retains the pending ID and detection timestamp");
        check(recovered.contexts.app_hang.hang_id == id && !Reflect.hasField(recovered.contexts.app_hang, "initial_event_id"), "No second-event correlation is needed");
        check(Reflect.field(recovered.tags, "hang.status") == "recovered", "Queryable final outcome");
        check(recovered.level == sentry.Level.Error, "Recovered hang remains one error event");
        check(recovered.contexts.app_hang.duration_min_ms == 6400 && recovered.contexts.app_hang.duration_max_ms == 6500
            && !recovered.contexts.app_hang.duration_is_lower_bound, "Recovery reports estimated duration bounds");
        check(recovered.exception.values[0].value.indexOf("6.4 and 6.5 seconds") >= 0, "Readable recovery duration range");
        var fatal = HangEvents.materialize({event: template, durationMs: 5000, id: id, detectedAtMs: 1300,
            durationMinMs: 4500, fatal: true, endReason: "process_exit"}, 999999, false);
        check(fatal.level == sentry.Level.Fatal && fatal.exception.values[0].mechanism.handled == false, "Confirmed process death makes the pending hang fatal");
        check(fatal.timestamp == 1.3 && fatal.contexts.app_hang.duration_ms == 5000, "Next-launch delay is never added to duration or detection time");
        check(fatal.contexts.app_hang.duration_max_ms == null && fatal.contexts.app_hang.duration_is_lower_bound, "No precise end duration is invented after termination");
        check(fatal.contexts.app_hang.end_reason == "process_exit" && !fatal.contexts.app_hang.recovered, "Fatal outcome is not recovery");
        template.exception.values[0].value = "redacted";
        template.tags = {};
        template.contexts.app_hang = {};
        var redacted = HangEvents.materialize({event: template, durationMs: 6500, id: id}, 7500, true);
        check(redacted.exception.values[0].value == "redacted" && Reflect.fields(redacted.tags).length == 0
            && Reflect.fields(redacted.contexts.app_hang).length == 0, "Recovery does not recreate redacted fields or overwrite custom messages");
    }
    static function privacy():Void {
        var transport = new MemoryTransport();
        var called = 0;
        var drop = false;
        var client = new sentry.Client({dsn: "https://key@example.com/1", transport: transport,
            beforeSend: function(event, hint) {
                called++;
                check(hint.hangSnapshot == true, "Snapshot hook is explicitly identified");
                event.user = null;
                event.contexts = {};
                event.breadcrumbs = [];
                return drop ? null : event;
            }});
        client.scope.setUser({id: "private"});
        client.scope.setContext("private", {secret: true});
        client.scope.addBreadcrumb({message: "private"});
        client.scope.addAttachment(sentry.Attachment.text("private"));
        var snapshot = client.prepareHangSnapshot(HangEvents.template("worker", 300));
        check(called == 1 && snapshot.user == null, "Snapshot passes through beforeSend");
        var event = HangEvents.materialize({event: snapshot, durationMs: 300}, 1000, false);
        client.capturePreparedHang(event);
        var sent = transport.event();
        check(sent.user == null && Reflect.fields(sent.contexts).length == 0 && sent.breadcrumbs.length == 0, "No scope merge after redaction");
        check(transport.requests[0].body.toString().indexOf('"type":"attachment"') == -1, "Hang reports omit scope attachments");
        check(called == 1, "No second application callback from background reporting");
        drop = true;
        check(client.prepareHangSnapshot(HangEvents.template("worker", 300)) == null, "beforeSend can drop snapshots");
        client.close();
        check(client.prepareHangSnapshot({}) == null, "Closed client cannot produce snapshots");
        var errors = 0;
        var failure = new sentry.Client({dsn: "https://key@example.com/1", transport: new MemoryTransport(),
            beforeSend: function(_, _) throw "failure", onError: function(_) errors++});
        check(failure.prepareHangSnapshot({}) == null && errors == 1, "Hook failure fails closed");
        failure.close();
        var sampled = new sentry.Client({dsn: "https://key@example.com/1", transport: new MemoryTransport(), sampleRate: 0});
        check(sampled.prepareHangSnapshot({}) == null, "Disabled sampling avoids even snapshot collection");
        sampled.close();
        var invalid = false;
        try new HangSettings({thresholdMs: 200, heartbeatIntervalMs: 100}) catch (_:Dynamic) invalid = true;
        check(invalid, "Reject thresholds too close to heartbeat interval");
    }
}
