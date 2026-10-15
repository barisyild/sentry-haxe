package sentry.transport;

typedef Request = {
    var url:String;
    var body:haxe.io.Bytes;
    var contentType:String;
    var timeoutMs:Int;
}
