package sentry.internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

class NativeBuild {
    public static function configure(kind:String):Array<Field> {
        var root = haxe.io.Path.normalize(haxe.io.Path.directory(sys.FileSystem.fullPath(Context.resolvePath("sentry/Sentry.hx"))) + "/../..");
        var xml = '<files id="haxe">';
        var link = "";
        if (kind == "native") {
            var include = Context.definedValue("sentry_native_include");
            xml += '<compilerflag value="-I' + escape(root + "/native/native") + '"/>';
            if (include != null) xml += '<compilerflag value="-I' + escape(sys.FileSystem.absolutePath(include)) + '"/>';
            if (Context.defined("sentry_native_static")) xml += '<compilerflag value="-DSENTRY_BUILD_STATIC"/>';
            var lib = Context.definedValue("sentry_native_lib");
            link = '<lib name="' + escape(lib == null ? (Context.defined("windows") ? "sentry.lib" : "-lsentry") : lib) + '"/>';
        } else {
            xml += '<compilerflag value="-I' + escape(root + "/native/cocoa") + '"/>';
            xml += '<compilerflag value="-fblocks"/><compilerflag value="-fmodules"/><compilerflag value="-fcxx-modules"/><compilerflag value="-fmodules-cache-path=objc-module-cache"/>';
            var framework = Context.definedValue("sentry_cocoa_framework");
            if (framework != null) {
                framework = sys.FileSystem.absolutePath(framework);
                xml += '<compilerflag value="-F' + escape(framework) + '"/>';
                link += '<flag value="-F' + escape(framework) + '"/>';
            }
            link += '<flag value="-framework"/><flag value="Sentry"/><flag value="-framework"/><flag value="Foundation"/>';
        }
        xml += '</files><target id="haxe">' + link + '</target>';
        Context.getLocalClass().get().meta.add(":buildXml", [macro $v{xml}], Context.currentPos());
        return Context.getBuildFields();
    }

    static function escape(value:String):String return StringTools.htmlEscape(value, true);
}
#end
