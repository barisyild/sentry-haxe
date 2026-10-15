package sentry.externs;

#if (cpp && android && lime && !sentry_portable)
/** Lime JNI bridge to the official Android SDK, including its NDK crash integration. */
class AndroidSdk {
    static final className = "io.sentry.haxe.SentryHaxeAndroid";
    static var initMethod:Dynamic;
    static var captureMethod:Dynamic;
    static var scopeMethod:Dynamic;
    static var flushMethod:Dynamic;
    static var closeMethod:Dynamic;
    public static function init(options:String):Void {
        if (initMethod == null) {
            initMethod = lime.system.JNI.createStaticMethod(className, "init", "(Ljava/lang/String;)V");
            captureMethod = lime.system.JNI.createStaticMethod(className, "capture", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
            scopeMethod = lime.system.JNI.createStaticMethod(className, "syncScope", "(Ljava/lang/String;)V");
            flushMethod = lime.system.JNI.createStaticMethod(className, "flush", "(I)Z");
            closeMethod = lime.system.JNI.createStaticMethod(className, "close", "(I)Z");
        }
        initMethod(options);
    }
    public static function capture(event:String, attachments:String):String return captureMethod(event, attachments);
    public static function syncScope(scope:String):Void scopeMethod(scope);
    public static function flush(timeoutMs:Int):Bool return flushMethod(timeoutMs);
    public static function close(timeoutMs:Int):Bool return closeMethod(timeoutMs);
}
#end
