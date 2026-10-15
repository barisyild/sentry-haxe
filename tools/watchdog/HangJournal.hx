import sentry.internal.hang.HangIncident;
import sentry.internal.hang.HangEvents;
import sentry.internal.hang.HangSettings;

/** Private, bounded pending-event store. Only finalized events are passed to the transport. */
class HangJournal {
    static inline var MAX_AGE_MS:Float = 604800000;
    static inline var MAX_RECORDS = 32;
    final fs:Dynamic = js.Syntax.code("require('node:fs')");
    final path:Dynamic = js.Syntax.code("require('node:path')");
    final process:Dynamic = js.Syntax.code("process");
    final directory:String;
    final parentPid:Int;
    final report:String->Void;
    var pendingId:String;
    var sending:Map<String, String> = [];

    public function new(root:String, dsn:String, parentPid:Int, report:String->Void) {
        this.parentPid = parentPid;
        this.report = report;
        var crypto:Dynamic = js.Syntax.code("require('node:crypto')");
        var project:String = crypto.createHash("sha256").update(dsn).digest("hex");
        directory = path.join(root, project);
        fs.mkdirSync(directory, {recursive: true, mode: 448}); // 0700
    }

    public static function alive(pid:Int):Bool {
        if (pid <= 1) return false;
        try { js.Syntax.code("process.kill({0}, 0)", pid); return true; }
        catch (error:Dynamic) return error.code != "ESRCH"; // Permission/unknown errors are not proof of exit.
    }
    static function number(value:Dynamic):Bool return (Std.isOfType(value, Int) || Std.isOfType(value, Float)) && Math.isFinite(value);

    function file(id:String):String return path.join(directory, id + ".json");
    function names():Array<String> return cast fs.readdirSync(directory);
    function remove(name:String):Void {
        try fs.unlinkSync(name) catch (error:Dynamic) { if (error.code != "ENOENT") report("Cannot remove hang cache record"); }
    }
    function write(name:String, record:Dynamic):Void {
        var temporary = name + ".tmp-" + process.pid;
        var text = sentry.internal.ProtocolJson.stringify(record);
        if (haxe.io.Bytes.ofString(text).length > HangSettings.MAX_SNAPSHOT_BYTES + 16384) throw "Hang cache record too large";
        try {
            fs.writeFileSync(temporary, text, {mode: 384}); // 0600; same-directory atomic replacement.
            fs.renameSync(temporary, name);
        } catch (error:Dynamic) { remove(temporary); throw error; }
    }
    function record(id:String, incident:Null<HangIncident>, event:Null<sentry.Event>):Dynamic return {
        version: 1, id: id, ownerPid: process.pid, parentPid: parentPid,
        storedAt: Date.now().getTime(), incident: incident, event: event
    };

    public function savePending(incident:HangIncident, force = false):Void {
        if (incident == null) { clearPending(); return; }
        if (!force && pendingId == incident.id) return;
        try {
            if (pendingId != incident.id) {
                clearPending();
                if (names().length >= MAX_RECORDS) { report("Hang cache is full"); return; }
            }
            write(file(incident.id), record(incident.id, incident, null));
            pendingId = incident.id;
        } catch (_:Dynamic) report("Cannot persist pending hang");
    }
    public function clearPending():Void {
        if (pendingId != null) remove(file(pendingId));
        pendingId = null;
    }

    public function finalize(incident:HangIncident, now:Float):sentry.Event {
        var event = HangEvents.materialize(incident, now, incident.recovered == true);
        try {
            var name = file(event.event_id);
            if (pendingId != event.event_id && names().length >= MAX_RECORDS) throw "Hang cache is full";
            write(name, record(event.event_id, null, event));
            if (pendingId == event.event_id) pendingId = null;
            sending[event.event_id] = name;
        } catch (_:Dynamic) {
            // Never leave a recovered episode classified as pending if persisting its outcome fails.
            clearPending();
            report("Cannot persist finalized hang; sending from memory");
        }
        return event;
    }

    public function delivered(id:String, status:Int):Void {
        if (status < 200 || status >= 300 || !sending.exists(id)) return;
        remove(sending[id]);
        sending.remove(id);
    }

    /** Replays only dead owners; an atomic rename claims a file for this process. */
    public function recover():Array<sentry.Event> {
        var events:Array<sentry.Event> = [];
        var pattern = ~/^([a-f0-9]{32})(?:\.sending-([0-9]+))?\.json$/;
        var temporary = ~/^[a-f0-9]{32}(?:\.sending-[0-9]+)?\.json\.tmp-([0-9]+)$/;
        for (name in names()) {
            if (temporary.match(name) && !alive(Std.parseInt(temporary.matched(1)))) { remove(path.join(directory, name)); continue; }
            if (events.length >= MAX_RECORDS || !pattern.match(name)) continue;
            var id = pattern.matched(1);
            var claimant = pattern.matched(2);
            if (claimant != null && alive(Std.parseInt(claimant))) continue;
            var source:String = path.join(directory, name);
            try {
                var stat:Dynamic = fs.lstatSync(source);
                if (!stat.isFile() || stat.size > HangSettings.MAX_SNAPSHOT_BYTES + 16384) continue;
                var data:Dynamic = haxe.Json.parse(fs.readFileSync(source, "utf8"));
                if (data.version != 1 || data.id != id || !Std.isOfType(data.ownerPid, Int)
                    || !Std.isOfType(data.parentPid, Int) || !number(data.storedAt)) continue;
                if (alive(data.ownerPid)) continue;
                if (Date.now().getTime() - (cast data.storedAt:Float) > MAX_AGE_MS) { remove(source); continue; }
                var event:sentry.Event = data.event;
                if (event == null) {
                    var incident:HangIncident = data.incident;
                    if (incident == null || incident.id != id || incident.event == null || !number(incident.durationMs)
                        || incident.durationMs < 0 || !number(incident.detectedAtMs)) continue;
                    var parentAlive = alive(data.parentPid);
                    // Another still-running application instance owns this episode.
                    if (parentAlive && data.parentPid != parentPid) continue;
                    incident.recovered = false;
                    incident.fatal = data.parentPid > 1 && !parentAlive;
                    incident.endReason = incident.fatal ? "process_exit" : "observer_lost";
                    event = HangEvents.materialize(incident, incident.detectedAtMs, false);
                }
                if (event.event_id != id) continue;
                var claimed:String = path.join(directory, id + ".sending-" + process.pid + ".json");
                fs.renameSync(source, claimed);
                // A crash after claim is recoverable without changing the event's ID or timestamp.
                var replay = record(id, null, event);
                replay.storedAt = data.storedAt; // Retries must not extend the retention period.
                write(claimed, replay);
                sending[id] = claimed;
                events.push(event);
            } catch (_:Dynamic) report("Cannot recover a hang cache record");
        }
        return events;
    }
}
