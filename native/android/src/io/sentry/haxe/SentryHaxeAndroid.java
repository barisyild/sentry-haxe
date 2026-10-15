package io.sentry.haxe;

import io.sentry.android.core.SentryAndroid;
import org.haxe.extension.Extension;

public final class SentryHaxeAndroid extends Extension {
    public static void init(String json) {
        SentryAndroid.init(mainContext.getApplicationContext(), options -> SentryHaxeBridge.configure(options, json));
    }
    public static String capture(String event, String attachments) { return SentryHaxeBridge.capture(event, attachments); }
    public static void syncScope(String scope) { SentryHaxeBridge.syncScope(scope); }
    public static boolean flush(int timeoutMs) { return SentryHaxeBridge.flush(timeoutMs); }
    public static boolean close(int timeoutMs) { return SentryHaxeBridge.close(timeoutMs); }
}
