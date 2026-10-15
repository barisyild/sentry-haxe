package sentry.internal;

/** ASCII JSON avoids target-dependent surrogate handling in Haxe/Flash/hxcpp encoders. */
class ProtocolJson {
    public static function stringify(value:Dynamic):String {
        var out = new StringBuf();
        write(out, value);
        return out.toString();
    }
    static function write(out:StringBuf, value:Dynamic):Void {
        if (value == null) { out.add("null"); return; }
        if (Std.isOfType(value, String)) { quote(out, value); return; }
        if (Std.isOfType(value, Bool)) { out.add(value ? "true" : "false"); return; }
        if (Std.isOfType(value, Float) || Std.isOfType(value, Int)) { out.add(Math.isFinite(value) ? Std.string(value) : "null"); return; }
        if (Std.isOfType(value, Array)) {
            out.add("[");
            var first = true;
            for (item in (cast value:Array<Dynamic>)) { if (!first) out.add(","); first = false; write(out, item); }
            out.add("]");
        } else {
            out.add("{");
            var first = true;
            for (key in Reflect.fields(value)) {
                var item = Reflect.field(value, key);
                if (Reflect.isFunction(item)) continue;
                if (!first) out.add(","); first = false;
                quote(out, key); out.add(":"); write(out, item);
            }
            out.add("}");
        }
    }
    static function quote(out:StringBuf, text:String):Void {
        out.add('"');
        for (i in 0...text.length) {
            var c = text.charCodeAt(i);
            if (c == 34) out.add('\\"');
            else if (c == 92) out.add('\\\\');
            else if (c < 32 || c >= 127) {
                if (c > 0xFFFF) {
                    c -= 0x10000;
                    out.add("\\u" + StringTools.hex(0xD800 + (c >> 10), 4));
                    out.add("\\u" + StringTools.hex(0xDC00 + (c & 1023), 4));
                } else out.add("\\u" + StringTools.hex(c, 4));
            } else out.addChar(c);
        }
        out.add('"');
    }
}
