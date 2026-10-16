import sentry.Sentry;

/** Real AVM2 coercions and stack traces; run only against the loopback harness. */
class FlashExceptionRuntimeTest {
    static var app:Dynamic;
    static var diagnostics = 0;

    static function nativeFailure():Void {
        throw new flash.errors.TypeError("native Flash failure");
    }

    static function main():Void {
        var type:Dynamic = flash.system.ApplicationDomain.currentDomain.getDefinition("flash.desktop.NativeApplication");
        app = type.nativeApplication;
        app.addEventListener("invoke", function(args:Dynamic) {
            Sentry.init({
                dsn: "http://public@127.0.0.1:" + args.arguments[0] + "/42",
                requestTimeoutMs: 2000,
                beforeSend: function(event, _) {
                    sentry.integrations.Proguard.apply(event, "1a876fc1-6ef9-4b93-9f35-11784da018ef");
                    return event;
                },
                onError: function(_) diagnostics++
            });
            try nativeFailure() catch (error:Dynamic) Sentry.captureException(error, {handled: false});
            Sentry.captureException(new haxe.Exception("outer", new haxe.Exception("root")));
            Sentry.captureException("string failure");
            Sentry.close(function(success) app.exit(success && diagnostics == 0 ? 0 : 1));
        });
        haxe.Timer.delay(function() app.exit(3), 8000);
    }
}
