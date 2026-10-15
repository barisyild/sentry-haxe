package sentry.internal.hang;

/** Call from an independent event loop. All clock values are local milliseconds. */
class HangObserver {
    final settings:HangSettings;
    var signal:Null<HangSignal>;
    var lastBeat:Float = 0;
    var lastObservation:Null<Float>;
    var nextReport:Float = 0;
    var reported = false;
    /** Not yet a report. Callers may persist it, but must not send it on detection. */
    public var pending(default, null):Null<HangIncident>;

    public function new(settings:HangSettings) this.settings = settings;

    /** A fresh active heartbeat finishes the previous episode using its pre-hang snapshot. */
    public function receive(next:HangSignal, now:Float):Null<HangIncident> {
        observeClock(now);
        if (signal != null && next.sequence == signal.sequence) return null;
        var recovered:Null<HangIncident> = null;
        // A pause or revoked snapshot cancels recovery reporting as well as future observations.
        if (signal != null && signal.active && next.active && signal.event != null && next.event != null) {
            if (pending != null) {
                recovered = sentry.internal.Values.copy(pending);
            } else if (!reported && now - lastBeat >= settings.thresholdMs && shouldReport(now)) {
                // The heartbeat can arrive just before the poll that would have detected the hang.
                recovered = createIncident(now);
            }
        }
        if (recovered != null) {
            recovered.recovered = true;
            recovered.durationMs = now - lastBeat;
            recovered.durationMinMs = Math.max(0, recovered.durationMs - 2 * settings.heartbeatIntervalMs);
            recovered.durationMaxMs = recovered.durationMs;
            recovered.endReason = "heartbeat_resumed";
        }
        pending = null;
        signal = next;
        lastBeat = now;
        reported = false;
        return recovered;
    }

    public function poll(now:Float):Null<HangIncident> {
        if (!observeClock(now)) return null;
        if (pending != null) {
            pending.durationMs = now - lastBeat;
            pending.durationMinMs = Math.max(0, pending.durationMs - settings.heartbeatIntervalMs);
        }
        if (signal == null || !signal.active || reported || now - lastBeat < settings.thresholdMs) return null;
        reported = true; // One attempt per hang, including filtering/sampling/rate-limit drops.
        if (signal.event == null || !shouldReport(now)) return null;
        pending = createIncident(now);
        return pending;
    }

    function createIncident(now:Float):HangIncident return {
        event: signal.event, durationMs: now - lastBeat, id: sentry.internal.Values.id(), recovered: false,
        detectedAtMs: now, durationMinMs: Math.max(0, now - lastBeat - settings.heartbeatIntervalMs)
    };

    public function reset():Void {
        pending = null;
        signal = null;
        reported = false;
        lastObservation = null;
    }

    function shouldReport(now:Float):Bool {
        if (now < nextReport || settings.sampleRate == 0 || Math.random() >= settings.sampleRate) return false;
        nextReport = now + settings.cooldownMs;
        return true;
    }

    function observeClock(now:Float):Bool {
        var previous = lastObservation;
        lastObservation = now;
        // If the observer itself stopped (sleep, debugger, process suspension), we have
        // no evidence that the application alone was unresponsive. Start a fresh grace period.
        if (previous != null && (now < previous || now - previous >= settings.thresholdMs)) {
            lastBeat = now;
            pending = null; // A duration spanning observer suspension is no longer trustworthy.
            if (now < previous) nextReport = 0;
            return false;
        }
        return true;
    }
}
