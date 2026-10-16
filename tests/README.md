# Verification

Run all commands from the repository root. `sh tests/run.sh` executes the portable suite under the Haxe interpreter and Node, compiles Flash/AIR, and type-checks the examples. The suite covers DSN parsing, binary envelopes, Unicode, isolated scopes, exception chains, filtering, queue limits, rate limits, flushing and lifecycle races.

## Flash exceptions and symbol metadata

```sh
haxe -cp src -cp tests -main FlashExceptionRuntimeTest -swf build/air-exceptions.swf -swf-version 32 -debug
cp tests/air-exceptions.xml build/air-exceptions.xml
ADL=/absolute/AIRSDK/bin/adl node tests/run-air-exceptions.cjs
```

This loopback-only AIR test exercises native Flash `Error` coercion, Haxe exception
chains and scalar exceptions through the real transport. It checks actual AVM2
class/method separation, debug source lines and ProGuard UUID metadata. The
portable suite also covers Unicode identifiers, constructors, static methods,
anonymous frames and preservation of existing native symbolication metadata.
Sentry server-side mapping generation/upload is the consuming application's job.

## Hang detection

`sh tests/run.sh` also executes `HangTest` in the interpreter and Node, builds the isolated worker and the external watchdog, and compiles monitor usage for Flash 11.1 and AIR. State-machine tests cover healthy pulses, stalled loops, one finalized event per episode, stable pending IDs and detection timestamps, estimated duration bounds, cooldowns, sampling, inactive periods, observer sleep/clock changes (including a fresh heartbeat arriving before the poll), recovery-only limits, snapshot revocation and privacy hooks.

```sh
# Real local TCP/HTTP; no live Sentry project:
node tests/run-watchdog.cjs

# Desktop AIR SDK; only the test application is intentionally stalled/suspended:
haxe -cp src -cp tests -cp examples -main FlashHangRuntimeTest -swf build/air-hangs.swf \
  -swf-version 32 -D air -resource build/sentry-hang-worker.swf@sentry-hang-worker
cp tests/air-hangs.xml build/air-hangs.xml
ADL=/absolute/AIRSDK/bin/adl node tests/run-air-hangs.cjs
ADL=/absolute/AIRSDK/bin/adl node tests/run-air-persistence.cjs
```

The AIR descriptor currently uses schema 51.0. The harness verifies exactly one error event arrives after recovery in Worker, external and recovery-only modes, and no event while paused/stopped, filtered or oversized. It checks duration bounds, preserved game context, redaction and worker shutdown before the close callback. On macOS/Linux it additionally uses SIGSTOP/SIGCONT on its own AIR child to verify the external helper observes the suspension and sends only after the runtime resumes, including a helper launched by the actual `AirWatchdogLauncher` / `NativeProcess` example under `extendedDesktop`. On Windows those process-suspension scenarios are skipped, so run a Windows-specific process-hang/packaging test before shipping.

The watchdog loopback harness also inspects pending files before any HTTP request, kills only a dummy test application to verify next-launch fatal reporting, distinguishes helper death from application death, checks IPC loss without a prior hang, and verifies cached upload retry with a stable ID and concurrent replay protection. On macOS/Linux, the AIR persistence harness suspends and terminates its own AIR child after detection, then launches the same application twice to verify one fatal event on the first relaunch and no duplicate on the second. It checks the original detection time, lower-bound duration, context and redaction through the actual NativeProcess launcher.

These tests require permission to listen on loopback; AIR requires a working desktop session. Recorded execution: AIR 51.4.1 on macOS ARM64, including Worker, recovery, pause, disposal, and whole-process suspension with the external helper. This does not verify Windows distribution, AIR mobile, browser Flash/Ruffle, a native minidump or actual production Sentry ingestion.

## Real JavaScript SDK

Install `@sentry/browser@10.22.0` into a separate test directory, then:

```sh
haxe -cp src -cp tests -main BrowserTest -js build/browser-test.js
NODE_PATH=/absolute/test-directory/node_modules node tests/run-browser.cjs
```

This runs the official SDK with a recording transport and disabled browser integrations. It verifies actual envelopes, IDs, scope restoration, exception stack frames, redaction, attachment isolation and flush.

## Real Java SDK

Set `SENTRY_JAR` to the absolute path of Maven Central's `io.sentry:sentry:8.24.0` JAR:

```sh
sh native/java/build.sh "$SENTRY_JAR"
haxe -cp src -cp tests -main TestMain -jvm build/tests-jvm.jar \
  --java-lib "$SENTRY_JAR" --java-lib native/java/build/sentry-haxe-bridge.jar
java -jar build/tests-jvm.jar
javac --release 8 -cp "$SENTRY_JAR:native/java/build/sentry-haxe-bridge.jar" \
  -d build/java-test tests/java/BridgeIntegrationTest.java
java -cp "build/java-test:$SENTRY_JAR:native/java/build/sentry-haxe-bridge.jar" BridgeIntegrationTest
```

Use `;` classpath separators on Windows. The Java integration fixture inspects events in the official SDK's `beforeSend` and returns null, so it does not transmit them.

## Real C SDK

Build sentry-native 0.11.3 with `SENTRY_BACKEND=none`, `SENTRY_TRANSPORT=none` and `SENTRY_BUILD_SHARED_LIBS=ON` for a network-free test. `NativeTest` installs a recording C transport before initialization. Supply the include directory, built library, and an absolute path for `SENTRY_HAXE_TEST_INCLUDE`:

```sh
haxe -cp src -cp tests -main NativeTest -cpp build/native-test \
  -D sentry_native_include=/absolute/sentry-native/include \
  -D sentry_native_lib=/absolute/native-build/libsentry.dylib \
  -D SENTRY_HAXE_TEST_INCLUDE=/absolute/sentry-haxe/tests/native
DYLD_LIBRARY_PATH=/absolute/native-build build/native-test/NativeTest
```

Adjust the library/runtime loader path on Linux/Windows and use `-D HXCPP_ARM64` for Apple Silicon when necessary. The fixture keeps its SDK database under `build/native-test-cache` and checks Unicode, IDs, final scope values, redaction and binary attachment bytes. The ordinary `TestMain` suite can also be compiled and executed with the same native include/library settings.

## Coverage recorded during implementation

- Haxe 5.0.0-preview.1 interpreter, JavaScript/Node 22, JVM/Java 25 and hxcpp/macOS ARM64: portable suite executed successfully.
- Official Sentry browser 10.22.0, Java 8.24.0 and sentry-native 0.11.3: adapter integration fixtures executed without live Sentry traffic.
- Flash Player 11.1/32 and AIR: SWFs compiled, including uncaught-error and hang integrations. Desktop AIR hang fixtures executed as described above; browser Flash and mobile runtime execution remain unverified.
- Android: Haxe JNI branch generated C++; the Java bridge compiled against real Android API classes, Lime's Extension class and Sentry Android Core 8.24.0. No APK/device/crash test was run.
- Cocoa: hxcpp Objective-C++ code compiled and linked against the existing Sentry 8.56.2 macOS framework. The bridge also passed a syntax check against the iOS arm64 framework using the iPhoneOS SDK and an iOS 15 deployment target. Runtime loading on macOS was refused because that existing framework's signature was not accepted. No iOS device/simulator crash test was run; framework signing/embedding remains part of the consuming application's build.
- TeaVM: the actual Lime HTTPRequest branch compiled to JVM bytecode. The local Lime checkout's custom `haxe.Timer` is incompatible with the installed Haxe 5 preview, so this isolated compile check shadowed that file with Haxe's standard Timer in a temporary classpath. No production code was patched and no Wasm/browser execution is claimed.
- Haxelib metadata, classpath and initialization macro were exercised with a temporary local haxelib repository; the user's global haxelib registrations were not changed.

Build logs/binaries are generated under ignored `build/`; downloaded SDKs stay outside the package. Device crash handling, symbol upload, release builds and live ingest need application-level validation.
