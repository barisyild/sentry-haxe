package sentry;

/** Sentry's wire format. Additional protocol fields can be supplied through Dynamic. */
typedef Event = {
    var ?event_id:String;
    var ?timestamp:Float;
    var ?platform:String;
    var ?level:Level;
    var ?message:Dynamic;
    var ?exception:Dynamic;
    var ?stacktrace:Dynamic;
    var ?threads:Dynamic;
    var ?debug_meta:Dynamic;
    var ?release:String;
    var ?environment:String;
    var ?dist:String;
    var ?logger:String;
    var ?transaction:String;
    var ?user:User;
    var ?tags:Dynamic;
    var ?extra:Dynamic;
    var ?contexts:Dynamic;
    var ?fingerprint:Array<String>;
    var ?breadcrumbs:Array<Breadcrumb>;
    var ?sdk:Dynamic;
}
