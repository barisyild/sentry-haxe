package sentry;

enum abstract Level(String) from String to String {
    var Debug = "debug";
    var Info = "info";
    var Warning = "warning";
    var Error = "error";
    var Fatal = "fatal";
}
