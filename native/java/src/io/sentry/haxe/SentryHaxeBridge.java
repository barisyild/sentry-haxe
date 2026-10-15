package io.sentry.haxe;

import io.sentry.*;
import java.io.StringReader;
import java.util.*;

/** Small public-API adapter. The official SDK owns persistence, transport and crash handling. */
public final class SentryHaxeBridge {
    private static JsonSerializer serializer = new JsonSerializer(new SentryOptions());
    private static Set<String> tags = new HashSet<>();
    private static Set<String> extras = new HashSet<>();
    private static Set<String> contexts = new HashSet<>();

    private SentryHaxeBridge() {}

    @SuppressWarnings("unchecked")
    private static Map<String, Object> object(String json) {
        Map<String, Object> value = serializer.deserialize(new StringReader(json), Map.class);
        if (value == null) throw new IllegalArgumentException("Invalid sentry-haxe JSON");
        return value;
    }

    public static void configure(SentryOptions options, String json) {
        Map<String, Object> values = object(json);
        options.setDsn((String) values.get("dsn"));
        options.setRelease((String) values.get("release"));
        options.setEnvironment((String) values.get("environment"));
        options.setDist((String) values.get("dist"));
        options.setDebug(Boolean.TRUE.equals(values.get("debug")));
        options.setMaxBreadcrumbs(((Number) values.get("maxBreadcrumbs")).intValue());
        options.setShutdownTimeoutMillis(((Number) values.get("shutdownTimeoutMs")).longValue());
        options.setSampleRate(1.0); // Haxe applies sampling once, before passing manual events here.
        serializer = new JsonSerializer(options);
        tags.clear(); extras.clear(); contexts.clear();
    }

    public static void init(String json) {
        Sentry.init(options -> configure(options, json));
    }

    @SuppressWarnings("unchecked")
    public static String capture(String json, String attachmentsJson) {
        SentryEvent event = serializer.deserialize(new StringReader(json), SentryEvent.class);
        if (event == null) throw new IllegalArgumentException("Invalid Sentry event");
        Hint hint = new Hint();
        List<Map<String, Object>> items = (List<Map<String, Object>>) object(attachmentsJson).get("items");
        for (Map<String, Object> item : items) {
            hint.addAttachment(new Attachment(decodeBase64((String) item.get("data")),
                (String) item.get("filename"), (String) item.get("content_type")));
        }
        // The Haxe event already contains the current breadcrumbs and event attachments.
        return Sentry.captureEvent(event, hint, scope -> {
            scope.clear();
        }).toString();
    }

    public static void syncScope(String json) {
        SentryEvent data = serializer.deserialize(new StringReader(json), SentryEvent.class);
        if (data == null) throw new IllegalArgumentException("Invalid Sentry scope");
        Sentry.configureScope(scope -> {
            scope.setUser(data.getUser());
            for (String key : tags) scope.removeTag(key);
            for (String key : extras) scope.removeExtra(key);
            for (String key : contexts) scope.removeContexts(key);
            tags = data.getTags() == null ? new HashSet<>() : new HashSet<>(data.getTags().keySet());
            extras = data.getExtras() == null ? new HashSet<>() : new HashSet<>(data.getExtras().keySet());
            contexts = new HashSet<>(Collections.list(data.getContexts().keys()));
            if (data.getTags() != null) for (String key : tags) scope.setTag(key, data.getTags().get(key));
            // IScope.setExtra only accepts String; getExtras exposes the official structured map.
            if (data.getExtras() != null) scope.getExtras().putAll(data.getExtras());
            for (String key : contexts) scope.setContexts(key, data.getContexts().get(key));
            scope.setLevel(data.getLevel());
            scope.setFingerprint(data.getFingerprints() == null ? Collections.emptyList() : data.getFingerprints());
            scope.setTransaction(data.getTransaction());
            scope.clearBreadcrumbs();
            if (data.getBreadcrumbs() != null) for (Breadcrumb b : data.getBreadcrumbs()) scope.addBreadcrumb(b);
        });
    }

    public static boolean flush(int timeoutMs) { Sentry.flush(timeoutMs); return true; }
    public static boolean close(int timeoutMs) { Sentry.flush(timeoutMs); Sentry.close(); return true; }

    // Avoid java.util.Base64's Android API 26 requirement. Input is produced by haxe.crypto.Base64.
    static byte[] decodeBase64(String input) {
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
        int bits = 0, count = 0;
        for (int i = 0; i < input.length(); i++) {
            char c = input.charAt(i);
            if (c == '=') break;
            int value = alphabet.indexOf(c);
            if (value < 0) throw new IllegalArgumentException("Invalid attachment base64");
            bits = (bits << 6) | value;
            count += 6;
            if (count >= 8) { count -= 8; output.write((bits >> count) & 255); }
        }
        return output.toByteArray();
    }
}
