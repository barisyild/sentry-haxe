package sentry.backend;

interface NativeScope {
    public function addBreadcrumb(breadcrumb:sentry.Breadcrumb):Void;
    public function clearBreadcrumbs():Void;
    public function setTag(key:String, value:String):Void;
    public function removeTag(key:String):Void;
    public function setExtra(key:String, value:Dynamic):Void;
    public function removeExtra(key:String):Void;
    public function setContext(key:String, value:Dynamic):Void;
    public function removeContext(key:String):Void;
    public function setUser(user:Null<sentry.User>):Void;
    public function setLevel(level:Null<sentry.Level>):Void;
    public function setEnvironment(environment:Null<String>):Void;
    public function setFingerprint(fingerprint:Null<Array<String>>):Void;
    public function clear():Void;
}
