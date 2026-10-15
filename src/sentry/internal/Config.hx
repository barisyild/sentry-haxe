package sentry.internal;

class Config {
    public final options:sentry.Options;
    public final enabled:Bool;
    public final dsn:Null<Dsn>;
    public final sampleRate:Float;
    public final maxBreadcrumbs:Int;
    public final maxQueueSize:Int;
    public final maxAttachmentBytes:Int;
    public final shutdownTimeoutMs:Int;
    public final requestTimeoutMs:Int;

    public function new(options:sentry.Options) {
        if (options == null) throw new haxe.Exception("Sentry options must not be null");
        this.options = options;
        enabled = options.enabled != false && options.dsn != null && StringTools.trim(options.dsn) != "";
        dsn = enabled ? new Dsn(options.dsn) : null;
        sampleRate = options.sampleRate == null ? 1.0 : options.sampleRate;
        if (!Math.isFinite(sampleRate) || sampleRate < 0 || sampleRate > 1)
            throw new haxe.Exception("sampleRate must be between 0 and 1");
        maxBreadcrumbs = value(options.maxBreadcrumbs, 100, "maxBreadcrumbs");
        maxQueueSize = value(options.maxQueueSize, 30, "maxQueueSize");
        maxAttachmentBytes = value(options.maxAttachmentBytes, 20 * 1024 * 1024, "maxAttachmentBytes");
        shutdownTimeoutMs = value(options.shutdownTimeoutMs, 2000, "shutdownTimeoutMs");
        requestTimeoutMs = value(options.requestTimeoutMs, 10000, "requestTimeoutMs");
    }

    static function value(v:Null<Int>, fallback:Int, name:String):Int {
        if (v == null) return fallback;
        if (v < 0) throw new haxe.Exception(name + " must not be negative");
        return v;
    }

    public function report(message:String):Void {
        try {
            if (options.onError != null) options.onError(message);
            else if (options.debug == true) haxe.Log.trace("[sentry-haxe] " + message, null);
        } catch (_:Dynamic) {}
    }
}
