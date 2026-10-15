package sentry.internal.hang;

/** Fallback: observes a delayed main-loop callback only AFTER the application recovers. */
class HangRecovery {
    final settings:HangSettings;
    var previous:Null<HangSignal>;
    var lastBeat:Float = 0;
    var nextReport:Float = 0;

    public function new(settings:HangSettings) this.settings = settings;
    public function reset():Void previous = null;

    public function beat(signal:HangSignal, now:Float):Null<HangIncident> {
        var old = previous;
        var duration = now - lastBeat;
        previous = signal;
        lastBeat = now;
        if (duration < 0) nextReport = 0;
        if (old == null || !old.active || !signal.active || old.event == null || signal.event == null || duration < settings.thresholdMs
            || duration > settings.maxRecoveryGapMs || now < nextReport || settings.sampleRate == 0
            || Math.random() >= settings.sampleRate) return null;
        nextReport = now + settings.cooldownMs;
        return {event: old.event, durationMs: duration, id: sentry.internal.Values.id(), recovered: true,
            detectedAtMs: now, durationMinMs: Math.max(0, duration - 2 * settings.heartbeatIntervalMs),
            durationMaxMs: duration, endReason: "heartbeat_resumed"};
    }
}
