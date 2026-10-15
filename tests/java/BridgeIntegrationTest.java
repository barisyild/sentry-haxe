import io.sentry.*;
import io.sentry.haxe.SentryHaxeBridge;
import java.util.*;

public class BridgeIntegrationTest {
    public static void main(String[] args) {
        try { run(); }
        catch (Throwable error) { Sentry.close(); throw error; }
    }
    private static void run() {
        List<SentryEvent> events = new ArrayList<>();
        List<Hint> hints = new ArrayList<>();
        Sentry.init(options -> {
            SentryHaxeBridge.configure(options, "{\"dsn\":\"https://key@example.com/1\",\"maxBreadcrumbs\":100,\"shutdownTimeoutMs\":1000}");
            options.setBeforeSend((event, hint) -> { events.add(event); hints.add(hint); return null; });
        });
        SentryHaxeBridge.syncScope("{\"user\":{\"id\":\"player\"},\"tags\":{\"room\":\"old\"},\"extra\":{\"redacted\":\"private\"},\"breadcrumbs\":[{\"message\":\"old\"}]}");
        SentryHaxeBridge.capture("{\"event_id\":\"1234567890abcdef1234567890abcdef\",\"timestamp\":1777777777.25,\"message\":{\"formatted\":\"Türkçe 😀\"},\"tags\":{\"room\":\"new\"},\"extra\":{},\"breadcrumbs\":[{\"message\":\"one\"}]}\n",
            "{\"items\":[{\"data\":\"AP8q\",\"filename\":\"bytes.bin\",\"content_type\":\"application/octet-stream\"}]}");
        if (events.size() != 1) throw new AssertionError("Event not processed");
        SentryEvent event = events.get(0);
        if (!event.getEventId().toString().equals("1234567890abcdef1234567890abcdef")) throw new AssertionError("Event ID");
        if (!event.getMessage().getFormatted().equals("Türkçe 😀")) throw new AssertionError("Unicode");
        if (!event.getTags().get("room").equals("new")) throw new AssertionError("Event scope override");
        if (event.getExtras() != null && event.getExtras().containsKey("redacted")) throw new AssertionError("Redacted extra reappeared");
        if (event.getUser() != null && "player".equals(event.getUser().getId())) throw new AssertionError("Removed scope user reappeared");
        if (event.getBreadcrumbs().size() != 1) throw new AssertionError("Duplicate breadcrumbs");
        if (!Arrays.equals(hints.get(0).getAttachments().get(0).getBytes(), new byte[]{0, (byte)255, 42})) throw new AssertionError("Binary attachment");
        SentryHaxeBridge.close(1000);
        System.out.println("PASS real Sentry Java SDK: deserialization, scope filtering, Unicode and attachment");
    }
}
