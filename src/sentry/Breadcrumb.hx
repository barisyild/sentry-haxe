package sentry;

typedef Breadcrumb = {
    var ?message:String;
    var ?category:String;
    var ?type:String;
    var ?level:Level;
    var ?timestamp:Float;
    var ?data:Dynamic;
}
