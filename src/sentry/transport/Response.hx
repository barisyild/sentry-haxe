package sentry.transport;

typedef Response = {
    var status:Int;
    var ?headers:Map<String, String>;
    var ?error:String;
}
