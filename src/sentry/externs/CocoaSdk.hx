package sentry.externs;

#if (cpp && (ios || sentry_cocoa) && !android && !sentry_portable)
@:include("SentryHaxeCocoa.h")
@:build(sentry.internal.NativeBuild.configure("cocoa"))
extern class CocoaSdk {
    @:native("sentry_haxe::initialize") public static function init(options:String):Void;
    @:native("sentry_haxe::capture") public static function capture(event:String, attachments:String):String;
    @:native("sentry_haxe::sync_scope") public static function syncScope(scope:String):Void;
    @:native("sentry_haxe::flush") public static function flush(timeoutMs:Int):Bool;
    @:native("sentry_haxe::close") public static function close(timeoutMs:Int):Bool;
}
#end
