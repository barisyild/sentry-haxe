package sentry.backend;

class BridgeData {
    public static function options(config:sentry.internal.Config):String {
        return sentry.internal.ProtocolJson.stringify({dsn: config.dsn.publicDsn, release: config.options.release, environment: config.options.environment,
            dist: config.options.dist, debug: config.options.debug == true, maxBreadcrumbs: config.maxBreadcrumbs, shutdownTimeoutMs: config.shutdownTimeoutMs,
            nativeOptions: config.options.nativeOptions});
    }
    public static function attachments(items:Array<sentry.Attachment>):String {
        return sentry.internal.ProtocolJson.stringify({items: [for (a in items) a.toBridge()]});
    }
}
