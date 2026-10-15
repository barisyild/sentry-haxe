package sentry;

class Sentry {
    public static inline var VERSION = "0.1.0";
    static var client:Client = new Client({enabled: false});
    public static function init(options:Options):Void {
        if (client.enabled || client.closing) throw new haxe.Exception("Wait for Sentry.close to complete before reinitializing it");
        client = new Client(options);
    }
    public static function isEnabled():Bool return client.enabled;
    public static function getClient():Client return client;
    public static function getCurrentScope():Scope return client.scope;
    public static function lastEventId():Null<String> return client.lastEventId;
    public static function configureScope(callback:Scope->Void):Void callback(client.scope);
    /** Synchronous only; capture inside the callback, before returning. */
    public static function withScope<T>(callback:Scope->T):T return client.withScope(callback);
    public static function setUser(user:Null<User>):Void client.scope.setUser(user);
    public static function setTag(key:String, value:String):Void client.scope.setTag(key, value);
    public static function setExtra(key:String, value:Dynamic):Void client.scope.setExtra(key, value);
    public static function setContext(key:String, value:Dynamic):Void client.scope.setContext(key, value);
    public static function setEnvironment(environment:String):Void client.scope.setEnvironment(environment);
    public static function addBreadcrumb(breadcrumb:Breadcrumb):Void client.addBreadcrumb(breadcrumb);
    public static function captureMessage(message:String, level:Level = Info, ?hint:Hint):Null<String> return client.captureMessage(message, level, hint);
    public static function captureException(error:Dynamic, ?hint:Hint):Null<String> return client.captureException(error, hint);
    public static function captureEvent(event:Event, ?hint:Hint):Null<String> return client.captureEvent(event, hint);
    public static function flush(timeoutMs = 2000, ?done:Bool->Void):Void client.flush(timeoutMs, done);
    public static function close(?done:Bool->Void):Void client.close(done);
}
