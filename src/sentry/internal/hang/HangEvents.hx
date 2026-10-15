package sentry.internal.hang;

import sentry.internal.Values;

class HangEvents {
    static inline var MESSAGE = "Flash main-loop heartbeat timed out";
    public static function template(mode:String, thresholdMs:Int, heartbeatIntervalMs:Int = 500):sentry.Event return {
        level: sentry.Level.Error,
        exception: {values: [{type: "ApplicationHang", value: MESSAGE,
            mechanism: {type: "AppHang", handled: true, synthetic: true}}]},
        fingerprint: ["sentry-haxe", "flash-app-hang"],
        tags: {"hang.monitor": mode, "hang.status": "ongoing", "hang.id": ""},
        contexts: {app_hang: {type: "app_hang", monitor: mode, threshold_ms: thresholdMs,
            heartbeat_interval_ms: heartbeatIntervalMs, duration_ms: 0, recovered: false, snapshot_age_ms: 0,
            status: "ongoing", hang_id: "", duration_min_ms: 0, duration_max_ms: null,
            duration_is_lower_bound: true, end_reason: null}}
    };

    public static function materialize(incident:HangIncident, nowMs:Float, recovered:Bool):sentry.Event {
        var event:sentry.Event = Values.copy(incident.event);
        var snapshotTime = event.timestamp;
        event.event_id = incident.id == null ? Values.id() : incident.id;
        var detectedAt = incident.detectedAtMs == null ? nowMs : incident.detectedAtMs;
        event.timestamp = detectedAt / 1000;
        var hangId = incident.id == null ? event.event_id : incident.id;
        var status = recovered ? "recovered" : incident.fatal == true ? "fatal" : "unresolved";
        if (incident.fatal == true && event.level == sentry.Level.Error) event.level = sentry.Level.Fatal;
        if (event.tags != null) {
            if (Reflect.hasField(event.tags, "hang.status")) Reflect.setField(event.tags, "hang.status", status);
            if (Reflect.hasField(event.tags, "hang.id")) Reflect.setField(event.tags, "hang.id", hangId);
        }
        if (event.exception != null) {
            var values:Array<Dynamic> = event.exception.values;
            if (values != null && values.length == 1 && values[0].type == "ApplicationHang" && values[0].value == MESSAGE) {
                var minimum = Math.floor((incident.durationMinMs == null ? incident.durationMs : incident.durationMinMs) / 100) / 10;
                var maximum = Math.ceil((incident.durationMaxMs == null ? incident.durationMs : incident.durationMaxMs) / 100) / 10;
                values[0].value = recovered
                    ? "Application recovered after an estimated main-loop hang between " + minimum + " and " + maximum + " seconds"
                    : (incident.fatal == true ? "Application terminated during a main-loop hang of at least " : "Main-loop hang observed for at least ")
                        + minimum + " seconds; recovery was not observed";
                if (incident.fatal == true) {
                    values[0].type = "FatalApplicationHang";
                    if (values[0].mechanism != null && Reflect.hasField(values[0].mechanism, "handled")) values[0].mechanism.handled = false;
                }
            }
        }
        // Respect redaction: never recreate a context removed by beforeSend.
        var context:Dynamic = event.contexts == null ? null : Reflect.field(event.contexts, "app_hang");
        if (context != null) {
            if (Reflect.hasField(context, "status")) Reflect.setField(context, "status", status);
            if (Reflect.hasField(context, "hang_id")) Reflect.setField(context, "hang_id", hangId);
            if (Reflect.hasField(context, "duration_min_ms")) Reflect.setField(context, "duration_min_ms", incident.durationMinMs == null ? incident.durationMs : incident.durationMinMs);
            if (Reflect.hasField(context, "duration_max_ms")) Reflect.setField(context, "duration_max_ms", recovered ? incident.durationMaxMs == null ? incident.durationMs : incident.durationMaxMs : null);
            if (Reflect.hasField(context, "duration_is_lower_bound")) Reflect.setField(context, "duration_is_lower_bound", !recovered);
            if (Reflect.hasField(context, "end_reason")) Reflect.setField(context, "end_reason", incident.endReason);
            if (Reflect.hasField(context, "duration_ms")) Reflect.setField(context, "duration_ms", incident.durationMs);
            if (Reflect.hasField(context, "recovered")) Reflect.setField(context, "recovered", recovered);
            if (Reflect.hasField(context, "snapshot_age_ms")) {
                // Keep the numeric type explicit across dynamic/boxed JVM field access.
                var age:Float = incident.durationMs;
                if (snapshotTime != null) age = Math.max(0, detectedAt - snapshotTime * 1000);
                Reflect.setField(context, "snapshot_age_ms", age);
            }
        }
        return event;
    }
}
