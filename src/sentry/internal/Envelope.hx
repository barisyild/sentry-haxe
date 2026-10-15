package sentry.internal;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import sentry.Attachment;
import sentry.Event;

class Envelope {
    public static function encode(dsn:Dsn, event:Event, attachments:Array<Attachment>):Bytes {
        var buffer = new BytesBuffer();
        line(buffer, {event_id: event.event_id, dsn: dsn.publicDsn, sdk: {name: "sentry.haxe", version: sentry.Sentry.VERSION}});
        var payload = Bytes.ofString(sentry.internal.ProtocolJson.stringify(event));
        line(buffer, {type: "event", length: payload.length, content_type: "application/json"});
        buffer.add(payload);
        buffer.addByte(10);
        for (a in attachments) {
            line(buffer, {type: "attachment", length: a.bytes.length, filename: a.filename, content_type: a.contentType, attachment_type: "event.attachment"});
            buffer.add(a.bytes);
            buffer.addByte(10);
        }
        return buffer.getBytes();
    }

    static function line(buffer:BytesBuffer, value:Dynamic):Void {
        buffer.add(Bytes.ofString(sentry.internal.ProtocolJson.stringify(value)));
        buffer.addByte(10);
    }
}
