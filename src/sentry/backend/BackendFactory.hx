package sentry.backend;

class BackendFactory {
    public static function create(config:sentry.internal.Config):Backend {
        if (config.options.transport != null) return new EnvelopeBackend(config, config.options.transport);
        #if (sentry_portable || flash || teavm)
        return new EnvelopeBackend(config, new sentry.transport.HttpTransport());
        #elseif js
        return new BrowserBackend(config);
        #elseif (cpp && android)
        return new AndroidBackend(config);
        #elseif (cpp && (ios || sentry_cocoa))
        return new CocoaBackend(config);
        #elseif cpp
        return new NativeBackend(config);
        #elseif (java || jvm)
        return new JavaBackend(config);
        #else
        throw new haxe.Exception("Unsupported Sentry target. Supply Options.transport for the portable implementation.");
        #end
    }
}
