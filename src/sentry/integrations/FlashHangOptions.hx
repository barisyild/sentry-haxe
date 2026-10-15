package sentry.integrations;

typedef FlashHangOptions = {
    /** Defaults to the embedded resource "sentry-hang-worker"; absent bytes use recovery mode. */
    var ?workerBytes:haxe.io.Bytes;
    var ?thresholdMs:Int;
    var ?heartbeatIntervalMs:Int;
    var ?cooldownMs:Int;
    /** Recovery-only gaps longer than this are ignored as possible sleep; default 60000. */
    var ?maxRecoveryGapMs:Int;
    /** Defaults to true. Background / minimized applications may be throttled by the runtime. */
    var ?pauseWhenInactive:Bool;
    var ?initiallyPaused:Bool;
    /** An already-running launcher watchdog, listening on IPv4 loopback. Takes priority over Worker. */
    var ?externalPort:Int;
    /** Per-launch random token printed by tools/watchdog; never use a constant token. */
    var ?externalToken:String;
}
