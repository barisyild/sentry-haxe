package sentry.externs;

#if (cpp && !android && !ios && !sentry_cocoa && !sentry_portable)
@:include("sentry.h") @:native("sentry_value_t") @:structAccess @:unreflective
extern class NativeValue {}
@:include("sentry.h") @:native("sentry_options_t") @:unreflective
extern class NativeOptions {}
@:include("sentry.h") @:native("sentry_scope_t") @:unreflective
extern class NativeScope {}
@:include("sentry.h") @:native("sentry_attachment_t") @:unreflective
extern class NativeAttachment {}
@:include("sentry.h") @:native("sentry_uuid_t") @:structAccess @:unreflective
extern class NativeId {}

@:include("SentryHaxeNative.h")
@:build(sentry.internal.NativeBuild.configure("native"))
extern class NativeSdk {
    @:native("sentry_haxe_configure") public static function configure(o:cpp.RawPointer<NativeOptions>):Void;
    @:native("sentry_options_new") public static function optionsNew():cpp.RawPointer<NativeOptions>;
    @:native("sentry_options_set_dsn") public static function setDsn(o:cpp.RawPointer<NativeOptions>, value:cpp.ConstCharStar):Void;
    @:native("sentry_options_set_release") public static function setRelease(o:cpp.RawPointer<NativeOptions>, value:cpp.ConstCharStar):Void;
    @:native("sentry_options_set_environment") public static function setEnvironment(o:cpp.RawPointer<NativeOptions>, value:cpp.ConstCharStar):Void;
    @:native("sentry_options_set_dist") public static function setDist(o:cpp.RawPointer<NativeOptions>, value:cpp.ConstCharStar):Void;
    @:native("sentry_options_set_debug") public static function setDebug(o:cpp.RawPointer<NativeOptions>, value:Int):Void;
    @:native("sentry_options_set_max_breadcrumbs") public static function setMaxBreadcrumbs(o:cpp.RawPointer<NativeOptions>, value:cpp.SizeT):Void;
    @:native("sentry_options_set_database_path") public static function setDatabasePath(o:cpp.RawPointer<NativeOptions>, value:cpp.ConstCharStar):Void;
    @:native("sentry_options_set_handler_path") public static function setHandlerPath(o:cpp.RawPointer<NativeOptions>, value:cpp.ConstCharStar):Void;
    @:native("sentry_options_set_shutdown_timeout") public static function setShutdownTimeout(o:cpp.RawPointer<NativeOptions>, value:cpp.UInt64):Void;
    @:native("sentry_init") public static function init(o:cpp.RawPointer<NativeOptions>):Int;
    @:native("sentry_close") public static function close():Int;
    @:native("sentry_flush") public static function flush(timeout:cpp.UInt64):Int;
    @:native("sentry_value_new_null") public static function nullValue():cpp.Struct<NativeValue>;
    @:native("sentry_value_new_bool") public static function boolValue(value:Int):cpp.Struct<NativeValue>;
    @:native("sentry_value_new_int32") public static function intValue(value:Int):cpp.Struct<NativeValue>;
    @:native("sentry_value_new_double") public static function doubleValue(value:Float):cpp.Struct<NativeValue>;
    @:native("sentry_value_new_string") public static function stringValue(value:cpp.ConstCharStar):cpp.Struct<NativeValue>;
    @:native("sentry_value_new_list") public static function listValue():cpp.Struct<NativeValue>;
    @:native("sentry_value_new_object") public static function objectValue():cpp.Struct<NativeValue>;
    @:native("sentry_value_append") public static function append(value:cpp.Struct<NativeValue>, child:cpp.Struct<NativeValue>):Int;
    @:native("sentry_value_set_by_key") public static function setKey(value:cpp.Struct<NativeValue>, key:cpp.ConstCharStar, child:cpp.Struct<NativeValue>):Int;
    @:native("sentry_local_scope_new") public static function newScope():cpp.RawPointer<NativeScope>;
    @:native("sentry_capture_event_with_scope") public static function captureEvent(event:cpp.Struct<NativeValue>, scope:cpp.RawPointer<NativeScope>):cpp.Struct<NativeId>;
    @:native("sentry_scope_attach_bytes") public static function attach(scope:cpp.RawPointer<NativeScope>, data:cpp.ConstCharStar, length:cpp.SizeT, filename:cpp.ConstCharStar):cpp.RawPointer<NativeAttachment>;
    @:native("sentry_attachment_set_content_type") public static function attachmentContentType(a:cpp.RawPointer<NativeAttachment>, type:cpp.ConstCharStar):Void;
    @:native("sentry_set_user") public static function setUser(user:cpp.Struct<NativeValue>):Void;
    @:native("sentry_remove_user") public static function removeUser():Void;
    @:native("sentry_set_tag") public static function setTag(key:cpp.ConstCharStar, value:cpp.ConstCharStar):Void;
    @:native("sentry_remove_tag") public static function removeTag(key:cpp.ConstCharStar):Void;
    @:native("sentry_set_extra") public static function setExtra(key:cpp.ConstCharStar, value:cpp.Struct<NativeValue>):Void;
    @:native("sentry_remove_extra") public static function removeExtra(key:cpp.ConstCharStar):Void;
    @:native("sentry_set_context") public static function setContext(key:cpp.ConstCharStar, value:cpp.Struct<NativeValue>):Void;
    @:native("sentry_remove_context") public static function removeContext(key:cpp.ConstCharStar):Void;
    @:native("sentry_add_breadcrumb") public static function addBreadcrumb(value:cpp.Struct<NativeValue>):Void;
}
#end
