import sentry.externs.NativeSdk;
import sentry.backend.NativeBackend;

@:cppFileCode('#include "NativeCapture.h"')
@:buildXml('<files id="haxe"><compilerflag value="-I${SENTRY_HAXE_TEST_INCLUDE}"/></files>')
class NativeTest {
    static function main():Void {
        var options = NativeSdk.optionsNew();
        NativeSdk.configure(options);
        NativeSdk.setDsn(options, "https://key@example.com/1");
        NativeSdk.setDatabasePath(options, haxe.io.Path.join([Sys.getCwd(), "build", "native-test-cache"]));
        untyped __cpp__("test_transport({0})", options);
        if (NativeSdk.init(options) != 0) throw "Native SDK initialization failed";
        NativeSdk.setTag("scope", "old");
        NativeSdk.setExtra("redacted", NativeSdk.stringValue("private"));
        NativeSdk.setContext("sdk-context", NativeBackend.value({value: "keep"}));
        NativeSdk.setContext("secret", NativeBackend.value({token: "private"}));
        var backend:NativeBackend = Type.createEmptyInstance(NativeBackend);
        @:privateAccess backend.previous = {contexts: {secret: {token: "private"}}};
        var bytes = haxe.io.Bytes.alloc(3); bytes.set(0, 0); bytes.set(1, 255); bytes.set(2, 42);
        var id = backend.capture({event_id: "1234567890abcdef1234567890abcdef", message: {formatted: "Native Türkçe 😀"},
            tags: {scope: "event"}, extra: {}, breadcrumbs: [{message: "one", timestamp: 1.0}]}, [new sentry.Attachment(bytes, "binary.dat")]);
        var envelope:String = untyped __cpp__("::String::create(test_envelope().c_str(), test_envelope().size())");
        var event:Dynamic = haxe.Json.parse(envelope.split("\n")[2]);
        if (id != event.event_id || id != "1234567890abcdef1234567890abcdef") throw "Native event ID mismatch";
        if (event.message.formatted != "Native Türkçe 😀") throw "Native Unicode mismatch";
        if (event.tags.scope != "event" || Reflect.hasField(event.extra, "redacted")) throw "Native scope overrode beforeSend";
        if (event.breadcrumbs.length != 1) throw "Native breadcrumbs mismatch";
        if (Reflect.hasField(event.contexts, "secret") || Reflect.field(event.contexts, "sdk-context").value != "keep") throw "Native context filtering mismatch";
        if (Reflect.hasField(event, "_sentry_haxe_processed")) throw "Internal marker leaked";
        if (envelope.indexOf('"filename":"binary.dat"') < 0) throw "Native attachment missing";
        if (!untyped __cpp__("test_binary_attachment()")) throw "Native attachment bytes changed";
        NativeSdk.close();
        trace("PASS real sentry-native: event ID, Unicode, scope filtering and attachment");
    }
}
