package sentry.internal;

class Values {
    /** Bounded, cycle-safe JSON snapshot. Never retain caller-owned mutable objects. */
    public static function copy(value:Dynamic, depth = 0, ?parents:Array<Dynamic>):Dynamic {
        if (value == null || Std.isOfType(value, String) || Std.isOfType(value, Bool)) return value;
        if (Std.isOfType(value, Float) || Std.isOfType(value, Int)) return Math.isFinite(value) ? value : null;
        if (Reflect.isFunction(value)) return "[Function]";
        if (depth >= 8) return "[MaxDepth]";
        if (parents == null) parents = [];
        for (parent in parents) if (parent == value) return "[Circular]";
        parents = parents.copy();
        parents.push(value);
        if (Std.isOfType(value, Date)) return (cast value:Date).toString();
        if (Std.isOfType(value, Array)) {
            var array:Array<Dynamic> = cast value;
            return [for (i in 0...Std.int(Math.min(array.length, 1000))) copy(array[i], depth + 1, parents)];
        }
        var result:Dynamic = {};
        if (Std.isOfType(value, haxe.ds.StringMap)) {
            var map:haxe.ds.StringMap<Dynamic> = cast value;
            var n = 0;
            for (key in map.keys()) {
                if (n++ >= 1000) break;
                Reflect.setField(result, key, copy(map.get(key), depth + 1, parents));
            }
        } else {
            var n = 0;
            for (key in Reflect.fields(value)) {
                if (n++ >= 1000) break;
                try Reflect.setField(result, key, copy(Reflect.field(value, key), depth + 1, parents)) catch (_:Dynamic) {}
            }
        }
        return result;
    }

    public static function merge(base:Dynamic, overlay:Dynamic):Dynamic {
        var result:Dynamic = base == null ? {} : copy(base);
        if (overlay != null) for (key in Reflect.fields(overlay)) Reflect.setField(result, key, copy(Reflect.field(overlay, key)));
        return result;
    }

    public static function id():String {
        var out = new StringBuf();
        for (i in 0...32) out.add("0123456789abcdef".charAt(i == 12 ? 4 : i == 16 ? 8 + Std.random(4) : Std.random(16)));
        return out.toString();
    }

    public static inline function now():Float return Date.now().getTime() / 1000.0;
}
