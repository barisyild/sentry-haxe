package sentry.integrations;

/** Explicit, disposable integration; preserves the application's default error handling. */
class UncaughtErrors {
    #if (flash || openfl)
    #if flash
    public static function install(info:flash.display.LoaderInfo):Void->Void {
        var handler = function(event:flash.events.UncaughtErrorEvent) sentry.Sentry.captureException(event.error, {handled: false});
        info.uncaughtErrorEvents.addEventListener(flash.events.UncaughtErrorEvent.UNCAUGHT_ERROR, handler);
        return function() info.uncaughtErrorEvents.removeEventListener(flash.events.UncaughtErrorEvent.UNCAUGHT_ERROR, handler);
    }
    #else
    public static function install(info:openfl.display.LoaderInfo):Void->Void {
        var handler = function(event:openfl.events.UncaughtErrorEvent) sentry.Sentry.captureException(event.error, {handled: false});
        info.uncaughtErrorEvents.addEventListener(openfl.events.UncaughtErrorEvent.UNCAUGHT_ERROR, handler);
        return function() info.uncaughtErrorEvents.removeEventListener(openfl.events.UncaughtErrorEvent.UNCAUGHT_ERROR, handler);
    }
    #end
    #end
}
