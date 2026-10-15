package sentry.externs;

#if js
#if sentry_node
@:jsRequire("@sentry/node")
#elseif sentry_browser_module
@:jsRequire("@sentry/browser")
#else
@:native("Sentry")
#end
extern class BrowserSdk {
    public static function init(options:Dynamic):Void;
    public static function captureEvent(event:Dynamic, ?hint:Dynamic):String;
    public static function captureException(error:Dynamic, ?hint:Dynamic):String;
    public static function captureMessage(message:String, ?level:String):String;
    public static function withScope(callback:BrowserScope->Void):Void;
    public static function getCurrentScope():BrowserScope;
    public static function addBreadcrumb(breadcrumb:Dynamic):Void;
    public static function flush(timeoutMs:Int):js.lib.Promise<Bool>;
    public static function close(timeoutMs:Int):js.lib.Promise<Bool>;
    public static function browserTracingIntegration(?options:Dynamic):Dynamic;
    public static function replayIntegration(?options:Dynamic):Dynamic;
    public static function replayCanvasIntegration(?options:Dynamic):Dynamic;
}

extern class BrowserScope {
    public function clear():Void;
    public function setUser(user:Dynamic):Void;
    public function setTag(key:String, value:String):Void;
    public function removeTag(key:String):Void;
    public function setExtra(key:String, value:Dynamic):Void;
    public function setContext(key:String, value:Dynamic):Void;
    public function setLevel(level:String):Void;
    public function setFingerprint(fingerprint:Array<String>):Void;
    public function setTransactionName(name:String):Void;
    public function addBreadcrumb(breadcrumb:Dynamic):Void;
    public function clearBreadcrumbs():Void;
    public function addAttachment(attachment:Dynamic):Void;
    public function clearAttachments():Void;
}
#end
