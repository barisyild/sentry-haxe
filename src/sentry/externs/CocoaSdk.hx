package sentry.externs;

#if (cpp && (ios || sentry_cocoa) && !android && !sentry_portable)
@:include("SentryHaxeCocoa.h")
@:build(sentry.internal.NativeBuild.configure("cocoa"))
extern class CocoaSdk {
    @:native("sentry_haxe::initialize") public static function init(options:String):Void;
    @:native("sentry_haxe::capture") public static function capture(event:String, attachments:String):String;
    @:native("sentry_haxe::add_breadcrumb") public static function addBreadcrumb(breadcrumb:String):Void;
    @:native("sentry_haxe::clear_breadcrumbs") public static function clearBreadcrumbs():Void;
    @:native("sentry_haxe::set_tag") public static function setTag(key:String, value:String):Void;
    @:native("sentry_haxe::remove_tag") public static function removeTag(key:String):Void;
    @:native("sentry_haxe::set_extra") public static function setExtra(key:String, value:String):Void;
    @:native("sentry_haxe::remove_extra") public static function removeExtra(key:String):Void;
    @:native("sentry_haxe::set_context") public static function setContext(key:String, value:String):Void;
    @:native("sentry_haxe::remove_context") public static function removeContext(key:String):Void;
    @:native("sentry_haxe::set_user") public static function setUser(user:String):Void;
    @:native("sentry_haxe::set_level") public static function setLevel(level:String):Void;
    @:native("sentry_haxe::set_environment") public static function setEnvironment(environment:String):Void;
    @:native("sentry_haxe::set_fingerprint") public static function setFingerprint(fingerprint:String):Void;
    @:native("sentry_haxe::clear_scope") public static function clearScope():Void;
    @:native("sentry_haxe::flush") public static function flush(timeoutMs:Int):Bool;
    @:native("sentry_haxe::close") public static function close(timeoutMs:Int):Bool;
}
#end
