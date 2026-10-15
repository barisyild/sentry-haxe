package sentry;

typedef Hint = {
    var ?originalException:Dynamic;
    var ?attachments:Array<Attachment>;
    var ?handled:Bool;
    /** A periodic, pre-hang snapshot. No exception has occurred yet; callbacks must be cheap. */
    var ?hangSnapshot:Bool;
}
