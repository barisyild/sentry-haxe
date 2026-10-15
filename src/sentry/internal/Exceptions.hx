package sentry.internal;

import haxe.CallStack;
import sentry.Event;

class Exceptions {
    public static function event(error:Dynamic, handled = true):Event {
        var values:Array<Dynamic> = [];
        var seen:Array<Dynamic> = [];
        var current = error;
        do {
            if (seen.indexOf(current) >= 0) break;
            seen.push(current);
            var name = "Error";
            var message = Std.string(current);
            var frames:Array<Dynamic> = [];
            if (Std.isOfType(current, haxe.Exception)) {
                var exception:haxe.Exception = cast current;
                name = Type.getClassName(Type.getClass(exception));
                message = exception.message;
                // CallStack.asArray is private in Haxe 4.3; use its public indexed API.
                var stack = exception.stack;
                frames = stackFrames([for (index in 0...stack.length) stack[index]]);
            } else {
                #if js
                if (Std.isOfType(current, js.lib.Error)) {
                    var e:js.lib.Error = cast current;
                    name = e.name;
                    message = e.message;
                    frames = parseStack(e.stack);
                }
                #elseif flash
                if (Std.isOfType(current, flash.errors.Error)) {
                    var e:flash.errors.Error = cast current;
                    name = e.name;
                    message = e.message;
                    frames = parseStack(e.getStackTrace());
                }
                #end
            }
            var value:Dynamic = {type: name, value: message, mechanism: {type: "generic", handled: handled}};
            if (frames.length > 0) value.stacktrace = {frames: frames};
            values.unshift(value);
            current = Std.isOfType(current, haxe.Exception) ? (cast current:haxe.Exception).previous : null;
        } while (current != null && values.length < 10);
        return {level: sentry.Level.Error, exception: {values: values}};
    }

    public static function stackFrames(stack:Array<StackItem>):Array<Dynamic> {
        var result:Array<Dynamic> = [];
        if (stack != null) for (item in stack) result.unshift(frame(item));
        return result;
    }

    static function frame(item:StackItem):Dynamic {
        return switch item {
            case CFunction: {"function": "[native]", in_app: false};
            case Module(m): {module: m, in_app: true};
            case Method(c, m): {module: c, "function": m, in_app: true};
            case LocalFunction(n): {"function": "local@" + n, in_app: true};
            case FilePos(s, file, line, column):
                var result:Dynamic = s == null ? {} : frame(s);
                result.filename = file;
                result.lineno = line;
                if (column != null) result.colno = column;
                result.in_app = true;
                result;
        };
    }

    public static function parseStack(stack:String):Array<Dynamic> {
        var result:Array<Dynamic> = [];
        if (stack == null) return result;
        for (line in stack.split("\n")) {
            var re = ~/^\s*(?:at\s+)?(.*?)\s*\(?((?:[a-zA-Z]+:\/\/|\/|[A-Za-z]:\\)[^\n]*?):([0-9]+)(?::([0-9]+))?\)?\s*$/;
            if (re.match(line)) {
                var f:Dynamic = {filename: re.matched(2), lineno: Std.parseInt(re.matched(3)), in_app: true};
                var fn = StringTools.trim(re.matched(1));
                if (StringTools.endsWith(fn, "@")) fn = fn.substr(0, fn.length - 1);
                if (fn != "") Reflect.setField(f, "function", fn);
                if (re.matched(4) != null) f.colno = Std.parseInt(re.matched(4));
                result.unshift(f);
            } else if (StringTools.startsWith(StringTools.trim(line), "at ")) {
                result.unshift({"function": StringTools.trim(line).substr(3), in_app: true});
            }
        }
        return result;
    }
}
