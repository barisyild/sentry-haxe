package sentry.externs;

#if ((java || jvm) && !teavm && !sentry_portable)
/** Bridge is built with native/java/build.sh and linked with --java-lib. */
@:native("io.sentry.haxe.SentryHaxeBridge")
extern class JavaSdk {
    public static function init(options:String):Void;
    public static function capture(event:String, attachments:String):String;
    public static function syncScope(scope:String):Void;
    public static function flush(timeoutMs:Int):Bool;
    public static function close(timeoutMs:Int):Bool;
}
#end
