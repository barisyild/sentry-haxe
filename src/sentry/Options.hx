package sentry;

typedef Options = {
    var ?dsn:String;
    var ?enabled:Bool;
    var ?debug:Bool;
    var ?release:String;
    var ?environment:String;
    var ?dist:String;
    var ?sampleRate:Float;
    var ?maxBreadcrumbs:Int;
    var ?maxQueueSize:Int;
    var ?maxAttachmentBytes:Int;
    var ?shutdownTimeoutMs:Int;
    var ?requestTimeoutMs:Int;
    var ?beforeSend:Event->Hint->Null<Event>;
    var ?beforeBreadcrumb:Breadcrumb->Null<Breadcrumb>;
    var ?onError:String->Void;
    /** Overrides the backend with the portable envelope implementation. Useful for tests/proxies. */
    var ?transport:sentry.transport.Transport;
    /** Official JS SDK options; Cocoa accepts the documented tracing, replay and hang options. */
    var ?nativeOptions:Dynamic;
    /** Writable, dedicated sentry-native cache directory. */
    var ?databasePath:String;
    var ?handlerPath:String;
}
