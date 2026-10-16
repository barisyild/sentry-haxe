package sentry.integrations;

/** Route named VM frames through Sentry's ProGuard symbolicator.
    Upload the matching mapping file with this UUID before shipping the application.
    This selects a symbolication format; event.platform and runtime context stay intact. */
class Proguard {
    public static function apply(event:sentry.Event, uuid:String):Void {
        if (event == null || uuid == null || uuid == "") return;
        if (!~/^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$/.match(uuid))
            throw new haxe.Exception("ProGuard mapping ID must be a UUID");
        var count = mark(event.stacktrace);
        if (event.exception != null && event.exception.values != null)
            for (value in (cast event.exception.values:Array<Dynamic>)) count += mark(value.stacktrace);
        if (event.threads != null && event.threads.values != null)
            for (thread in (cast event.threads.values:Array<Dynamic>)) count += mark(thread.stacktrace);
        if (count == 0) return;
        if (event.debug_meta == null) event.debug_meta = {};
        if (event.debug_meta.images == null) event.debug_meta.images = [];
        var images:Array<Dynamic> = event.debug_meta.images;
        uuid = uuid.toLowerCase();
        for (image in images) if (image.type == "proguard" && image.uuid == uuid) return;
        images.push({type: "proguard", uuid: uuid});
    }

    static function mark(stack:Dynamic):Int {
        if (stack == null || stack.frames == null) return 0;
        var count = 0;
        for (frame in (cast stack.frames:Array<Dynamic>)) {
            if (frame == null || frame.module == null || Reflect.field(frame, "function") == null) continue;
            if (frame.platform != null && frame.platform != "other" && frame.platform != "java") continue;
            // Sentry uses the frame platform to select its ProGuard name resolver.
            // The VM itself may be AVM2, JVM or TeaVM; no Java runtime context is invented.
            frame.platform = "java";
            count++;
        }
        return count;
    }
}
