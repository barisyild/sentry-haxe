package sentry.internal.hang;

/** Serializable settings shared with the isolated worker / launcher watchdog. */
class HangSettings {
    public var thresholdMs:Int;
    public var heartbeatIntervalMs:Int;
    public var cooldownMs:Int;
    public var maxRecoveryGapMs:Int;
    public var sampleRate:Float;
    public static inline var MAX_SNAPSHOT_BYTES = 262144;

    public function new(?options:Dynamic, sampleRate:Null<Float> = 1.0) {
        if (options == null) options = {};
        thresholdMs = integer(options, "thresholdMs", 5000, 200, 3600000);
        heartbeatIntervalMs = integer(options, "heartbeatIntervalMs", 500, 50, 60000);
        cooldownMs = integer(options, "cooldownMs", 60000, 0, 86400000);
        maxRecoveryGapMs = integer(options, "maxRecoveryGapMs", Std.int(Math.max(60000, thresholdMs)), thresholdMs, 86400000);
        if (thresholdMs < heartbeatIntervalMs * 3)
            throw new haxe.Exception("thresholdMs must be at least three heartbeat intervals");
        if (sampleRate == null || !Math.isFinite(sampleRate) || sampleRate < 0 || sampleRate > 1)
            throw new haxe.Exception("Invalid hang sampleRate");
        this.sampleRate = sampleRate;
    }

    static function integer(options:Dynamic, name:String, fallback:Int, minimum:Int, maximum:Int):Int {
        var value:Dynamic = Reflect.field(options, name);
        if (value == null) return fallback;
        if ((!Std.isOfType(value, Int) && !Std.isOfType(value, Float)) || !Math.isFinite(value)
            || value != Math.floor(value) || value < minimum || value > maximum)
            throw new haxe.Exception("Invalid hang setting: " + name);
        return Std.int(value);
    }

    public function serialize():Dynamic return {
        thresholdMs: thresholdMs, heartbeatIntervalMs: heartbeatIntervalMs,
        cooldownMs: cooldownMs, maxRecoveryGapMs: maxRecoveryGapMs, sampleRate: sampleRate
    };
}
