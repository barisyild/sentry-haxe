package sentry.internal;

import sentry.transport.Response;

class RateLimits {
    var limits:Map<String, Float> = [];
    public function new() {}
    public function limited(category:String, now:Float):Bool {
        return (limits.exists("all") && limits["all"] > now) || (limits.exists(category) && limits[category] > now);
    }

    public function update(response:Response, now:Float):Void {
        var custom = header(response, "x-sentry-rate-limits");
        if (custom != null && custom != "") {
            for (part in custom.split(",")) {
                var fields = StringTools.trim(part).split(":");
                if (fields.length < 2) continue;
                var seconds = Std.parseFloat(fields[0]);
                if (!Math.isFinite(seconds)) seconds = 60;
                var until = now + Math.max(0, seconds);
                var categories = StringTools.trim(fields[1]);
                if (categories == "") extend("all", until);
                else for (category in categories.split(";")) {
                    category = StringTools.trim(category);
                    if (category == "error" || category == "attachment") extend(category, until);
                }
            }
        } else if (response.status == 429) {
            var retry = header(response, "retry-after");
            var seconds = retry == null ? Math.NaN : Std.parseFloat(retry);
            if (!Math.isFinite(seconds) && retry != null) {
                var re = ~/^[A-Za-z]+, ([0-9]+) ([A-Za-z]+) ([0-9]+) ([0-9]+):([0-9]+):([0-9]+) GMT$/;
                if (re.match(retry)) {
                    var month = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].indexOf(re.matched(2));
                    if (month >= 0) {
                        var date = new Date(Std.parseInt(re.matched(3)), month, Std.parseInt(re.matched(1)), Std.parseInt(re.matched(4)), Std.parseInt(re.matched(5)), Std.parseInt(re.matched(6)));
                        seconds = (date.getTime() - date.getTimezoneOffset() * 60000) / 1000 - now;
                    }
                }
            }
            if (!Math.isFinite(seconds)) seconds = 60;
            extend("all", now + Math.max(0, seconds));
        }
    }

    function extend(category:String, until:Float):Void {
        if (!limits.exists(category) || until > limits[category]) limits[category] = until;
    }

    static function header(response:Response, key:String):Null<String> {
        if (response.headers != null) for (name in response.headers.keys()) if (name.toLowerCase() == key) return response.headers[name];
        return null;
    }
}
