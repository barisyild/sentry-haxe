package sentry.internal.hang;

typedef HangIncident = {
    var event:sentry.Event;
    var durationMs:Float;
    /** Assigned at detection; the pending incident is sent only after its outcome is known. */
    var ?id:String;
    var ?recovered:Bool;
    var ?detectedAtMs:Float;
    var ?durationMinMs:Float;
    var ?durationMaxMs:Float;
    var ?fatal:Bool;
    var ?endReason:String;
}
