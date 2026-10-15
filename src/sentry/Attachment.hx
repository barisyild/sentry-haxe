package sentry;

import haxe.io.Bytes;

class Attachment {
    public final bytes:Bytes;
    public final filename:String;
    public final contentType:String;

    public function new(bytes:Bytes, filename:String, contentType = "application/octet-stream") {
        if (bytes == null || filename == null || filename.length == 0)
            throw new haxe.Exception("Attachment requires bytes and a filename");
        this.bytes = bytes;
        this.filename = filename;
        this.contentType = contentType;
    }

    public static function text(text:String, filename = "attachment.txt"):Attachment {
        return new Attachment(Bytes.ofString(text), filename, "text/plain; charset=utf-8");
    }

    public function toBridge():Dynamic {
        return {data: haxe.crypto.Base64.encode(bytes), filename: filename, content_type: contentType};
    }
}
