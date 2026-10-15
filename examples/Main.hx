import sentry.Sentry;
import sentry.Attachment;

class Main {
    static function main():Void {
        // Supply your project's public DSN. Empty DSN intentionally disables reporting.
        Sentry.init({
            dsn: "",
            release: "my-game@1.0.0",
            environment: "development",
            beforeSend: function(event, hint) {
                if (event.extra != null) Reflect.deleteField(event.extra, "password");
                return event;
            }
        });
        Sentry.setUser({id: "player-42"});
        Sentry.setTag("room", "square");
        Sentry.addBreadcrumb({category: "navigation", message: "Entered square"});
        Sentry.withScope(function(scope) {
            scope.setExtra("assetId", "character-1");
            scope.addAttachment(Attachment.text("asset loading details", "loader.txt"));
            try {
                throw new haxe.Exception("Example asset load failure");
            } catch (error:haxe.Exception) {
                Sentry.captureException(error);
            }
        });
        Sentry.close();
    }
}
