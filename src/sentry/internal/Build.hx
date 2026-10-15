package sentry.internal;

#if macro
class Build {
    /** Compile an isolated Worker with the same SDK sources and embed it in the host SWF. */
    public static function embedHangWorker():Void {
        if (!haxe.macro.Context.defined("flash")) return;
        var source = haxe.io.Path.directory(haxe.io.Path.directory(sys.FileSystem.fullPath(haxe.macro.Context.resolvePath("sentry/Sentry.hx"))));
        var root = haxe.io.Path.directory(source);
        var output = root + "/build/sentry-hang-worker.swf";
        if (!sys.FileSystem.exists(root + "/build")) sys.FileSystem.createDirectory(root + "/build");
        if (Sys.command("haxe", ["-cp", source, "-main", "sentry.internal.hang.WorkerMain", "-swf", output, "-swf-version", "11.4"]) != 0)
            haxe.macro.Context.fatalError("Cannot compile the Sentry hang Worker", haxe.macro.Context.currentPos());
        haxe.macro.Context.addResource("sentry-hang-worker", sys.io.File.getBytes(output));
    }

    public static function init():Void {
        if (haxe.macro.Context.defined("cpp") && (haxe.macro.Context.defined("ios") || haxe.macro.Context.defined("sentry_cocoa"))) {
            haxe.macro.Compiler.define("objc");
            haxe.macro.Compiler.define("file_extension", "mm");
        }
    }
}
#end
