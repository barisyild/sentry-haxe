package sentry.internal.hang;

typedef HangSignal = {
    var sequence:Int;
    var active:Bool;
    /** Already passed through the application's beforeSend; null revokes the previous snapshot. */
    var event:Null<sentry.Event>;
}
