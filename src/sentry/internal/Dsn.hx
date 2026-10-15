package sentry.internal;

class Dsn {
    public final publicDsn:String;
    public final envelopeUrl:String;
    public final publicKey:String;
    public final projectId:String;

    public function new(value:String) {
        var re = ~/^(https?):\/\/([^\/@:]+)(?::[^\/@]*)?@(\[[0-9a-fA-F:]+\]|[^\/:?#]+)(:[0-9]+)?(\/[^?#]*)$/;
        if (value == null || !re.match(value)) throw new haxe.Exception("Invalid Sentry DSN");
        var scheme = re.matched(1);
        publicKey = re.matched(2);
        var host = re.matched(3);
        var port = re.matched(4);
        if (port == null) port = "";
        var path = re.matched(5);
        var slash = path.lastIndexOf("/");
        projectId = path.substr(slash + 1);
        if (!~/^[0-9]+$/.match(projectId)) throw new haxe.Exception("Sentry DSN requires a numeric project ID");
        var prefix = path.substr(0, slash);
        var origin = scheme + "://" + host + port;
        publicDsn = scheme + "://" + publicKey + "@" + host + port + path;
        envelopeUrl = origin + prefix + "/api/" + projectId + "/envelope/?sentry_version=7&sentry_key="
            + StringTools.urlEncode(publicKey) + "&sentry_client=sentry.haxe%2F" + sentry.Sentry.VERSION;
    }
}
