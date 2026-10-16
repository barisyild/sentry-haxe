# sentry-haxe

Unofficial cross-platform Haxe error-reporting library. One `sentry.Sentry` API uses official Sentry SDKs where available, with a Haxe envelope implementation for Flash/AIR and TeaVM. Haxe 4.3+; the core has no haxelib dependencies.

| Target | Backend | Additional dependency |
| --- | --- | --- |
| HTML5 / JavaScript | Typed externs for the official browser SDK | `@sentry/browser` 8+ or a matching browser bundle; tested with 10.22.0 |
| iOS / hxcpp | Objective-C++ bridge and externs for Sentry Cocoa | Sentry framework linked into the application; tested with Sentry Cocoa 8.56.2 |
| Android / hxcpp | Lime JNI bridge to Sentry Android, including NDK integration | Lime; Gradle resolves `io.sentry:sentry-android:8.24.0` |
| Windows / Linux / macOS / hxcpp | Direct C externs for sentry-native | sentry-native 0.11.3+ headers and library |
| Java / JVM | Java externs and a small public-API bridge | `io.sentry:sentry:8.24.0` and the bridge JAR |
| Flash / AIR, including AIR on mobile | Haxe envelope SDK with asynchronous `URLLoader` | Flash Player 11.1+; appropriate network sandbox permissions |
| TeaVM / Wasm through JVM | Haxe envelope SDK over Lime HTTPRequest | A Lime build with TeaVM/Wasm HTTPRequest support |

`flash` takes priority over `android`/`ios`, and `teavm` takes priority over `jvm`. AIR therefore uses the portable implementation. macOS defaults to sentry-native; `-D sentry_cocoa` selects Cocoa instead. Other Haxe targets can supply a custom transport but are outside the initial supported matrix.

## Install

Install from the public Git repository, including in CI:

```sh
haxelib git sentry-haxe https://github.com/barisyild/sentry-haxe.git main --always
```

For local development, register your checkout instead:

```sh
haxelib dev sentry-haxe /absolute/path/to/sentry-haxe
```

Use `-lib sentry-haxe`, or add this to a Lime/OpenFL project:

```xml
<haxelib name="sentry-haxe" />
```

Haxelib supplies the source classpath and initialization macro; no project-relative `path` or manual `-cp` is needed. Build tools can locate the package root with `haxelib libpath sentry-haxe`. In CI, install after restoring any haxelib cache so the requested Git branch is refreshed on every run.

The package includes `haxelib.json`, `extraParams.hxml` and `include.xml`. No SDK downloads run from compiler macros. Native SDKs are application build dependencies, not bundled binaries.

## Shared API

```haxe
import sentry.Sentry;
import sentry.Attachment;

Sentry.init({
    dsn: "https://public-key@sentry.example.com/42",
    release: "example-app@1.0.0",
    environment: "production",
    maxBreadcrumbs: 100,
    beforeSend: (event, hint) -> {
        // Returning null discards the event. hint.originalException is available.
        return event;
    }
});

Sentry.setUser({id: "42", username: "player"});
Sentry.setTag("room", "square");
Sentry.setContext("game", {server: "tr", roomKey: "square"});
Sentry.addBreadcrumb({category: "navigation", message: "Entered square"});

Sentry.withScope(scope -> {
    scope.setExtra("assetId", "character-1");
    scope.addAttachment(Attachment.text("loader details", "loader.txt"));
    try loadAsset() catch (error:Dynamic) Sentry.captureException(error);
});

Sentry.captureMessage("Client ready");
Sentry.setUser(null); // Logout.
Sentry.flush(2000, success -> trace(success));
// On shutdown, or before reinitializing:
Sentry.close(success -> trace(success));
```

Captures return a 32-character event ID when accepted, or `null` when disabled, filtered, sampled out or rejected by the portable queue. An ID is not a delivery receipt. An empty DSN disables the library without constructing a native backend. Malformed configuration throws during initialization; capture/hook failures go to `onError` and do not interrupt the game.

`withScope` is synchronous and restores the previous scope even when the callback throws. Capture inside the callback; do not keep that scope for async work. A client belongs to one application thread. Native SDKs are process-wide: use one active native client, and wait for the `close` callback before reinitializing. The static facade enforces this lifecycle.

Scope supports user, tags, structured extras/contexts, environment, level, fingerprint, transaction name, bounded breadcrumbs and attachments. Events are snapshots, exception chains retain stack frames oldest first, and circular values are normalized. Attachments accept `haxe.io.Bytes`; portable envelopes preserve binary contents and use byte lengths.

## Platform setup

### HTML5

Load an official Sentry browser bundle **before** the compiled Haxe program, exposing global `Sentry`. Use SDK 8 or newer; the adapter was tested with the 10.22.0 tracing/replay bundle. A missing SDK produces an explicit initialization error.

For a CommonJS-aware bundler, install `@sentry/browser` and compile with `-D sentry_browser_module`. `-D sentry_node` selects `@sentry/node` for applications that already use it. `nativeOptions` passes additional JS SDK options by reference, including integrations, replay and tracing; the facade supplies DSN, release, environment and breadcrumb limits and applies its own sampling once. Advanced APIs remain accessible as `sentry.externs.BrowserSdk`.

Browser `nativeOptions.beforeSend` receives `hint.sentryHaxeProcessed == true` for events already filtered by the Haxe pipeline. Use this marker to avoid repeating application enrichment or side effects when handling both native and Haxe captures.

### iOS / Cocoa

Add the official Sentry framework through SPM or XCFramework and embed/sign dynamic frameworks in the application. Use the framework search path configured by your build, or pass `-D sentry_cocoa_framework=/absolute/path/to/directory-containing-Sentry.framework` for the correct device/simulator slice. Do not pass the XCFramework root.

The haxelib initialization macro enables Objective-C++ for hxcpp and links Sentry/Foundation. Plain `-cp src` builds must also pass `--macro sentry.internal.Build.init()`. The adapter supports hxcpp's manual reference counting. Cocoa owns native crash capture, caching and transport. No `hx-ios-uikit` dependency is needed.

Cocoa `nativeOptions` accepts `tracesSampleRate`, `enableAppHangTracking`, `enableAppHangTrackingV2`, `enableReportNonFullyBlockingAppHangs`, `appHangTimeoutInterval`, `enableCaptureFailedRequests`, `attachScreenshot`, `enableUserInteractionTracing`, `startProfiler` and `sessionReplay` rates/masking where supported by the platform.

For Cocoa 8 on iOS, use `nativeOptions: {enableAppHangTracking: true, enableAppHangTrackingV2: true, appHangTimeoutInterval: 5.0}` to opt into duration tracking and next-launch fatal hang reports. The bridge only calls the V2 setter when the installed SDK exposes it; newer Cocoa SDKs use V2 without that opt-in setter. Cocoa owns its file cache and native hang detection.

### Android

Lime's `include.xml` installs the Gradle module under `native/`. It includes shared Java sources, R8 keep rules and an Internet permission. Manifest auto-init is disabled so the supplied Haxe options initialize the SDK once. Call `Sentry.init` after Lime initializes its Android activity/context. Use Android API 21+ and a Gradle/compile SDK toolchain compatible with Sentry Android 8.24.0.

### Desktop C++

Build/install [sentry-native](https://github.com/getsentry/sentry-native/tree/0.11.3), then supply:

```sh
haxe -lib sentry-haxe -cp examples -main Main -cpp build/app \
  -D sentry_native_include=/absolute/sdk/include \
  -D sentry_native_lib=/absolute/sdk/lib/libsentry.a \
  -D sentry_native_static
```

For shared libraries omit `sentry_native_static`, point `sentry_native_lib` to the `.dylib`/`.so`/`.lib`, and package its runtime library. Static builds must link the SDK's platform/transport dependencies as specified by its CMake installation. Without overrides, compiler/library search paths must resolve `sentry.h` and `sentry`.

Configure a dedicated writable `databasePath`, and a `handlerPath` when your chosen crash backend needs a helper executable. Package the helper and upload debug symbols separately. A build with `SENTRY_BACKEND=none` does not capture native crashes. User, tag, extra and context changes are mirrored to the native crash scope; Haxe breadcrumb history, level and fingerprint are guaranteed for manual events on this backend. The C callback preserves manual `beforeSend` edits after native scope merging without calling Haxe from crash handlers.

### JVM

Obtain `sentry-8.24.0.jar` from Maven Central, then:

```sh
sh native/java/build.sh /absolute/path/sentry-8.24.0.jar
haxe -lib sentry-haxe -cp examples -main Main -jvm build/example.jar \
  --java-lib /absolute/path/sentry-8.24.0.jar \
  --java-lib native/java/build/sentry-haxe-bridge.jar
```

Keep the referenced JARs on the runtime classpath. The bridge is compiled for Java 8. TeaVM deliberately bypasses this Java SDK: its browser runtime uses the portable transport through Lime rather than desktop JVM threads or native libraries.

### Flash / AIR / TeaVM

Flash's implementation sends authenticated envelopes over HTTPS using a public DSN key in the URL; a legacy DSN's secret key is never sent. Hosted SWFs need a server `crossdomain.xml` that allows the application origin and request content type. AIR networking permissions and TeaVM's browser CORS rules also apply. A same-origin ingestion proxy can supply the necessary policy when direct access to Sentry is unavailable.

Defaults: 30 pending envelopes, 100 breadcrumbs, 20 MiB total attachment bytes per event, 10-second request timeout. `maxQueueSize`, `maxAttachmentBytes`, `requestTimeoutMs` and `shutdownTimeoutMs` override them. The queue is bounded and serial; it handles `X-Sentry-Rate-Limits`, `Retry-After` and 429 backoff, including separate attachment limits. Flash Player does not expose arbitrary response headers; it still honors 429 with a 60-second fallback. AIR and TeaVM read headers when their runtime/server exposes them. Events queued during an error limit are discarded, not retried indefinitely.

The application’s portable queue is memory-only: closing the process loses unsent data. Ordinary portable captures have no offline replay, session health, tracing, profiling or hard-crash capture. The separate desktop watchdog has its own bounded hang journal, described below. Official backends provide their native features; the shared API here focuses on errors, messages and scope data. `beforeSend`, `beforeBreadcrumb` and `sampleRate` apply to events submitted through this Haxe API; automatically captured native events use their SDK's own configuration. JS native integration options can be passed through `nativeOptions`.

For Flash/OpenFL uncaught errors, install explicitly and dispose with the returned function:

```haxe
var removeHandler = sentry.integrations.UncaughtErrors.install(stage.loaderInfo);
// Later: removeHandler();
```

This listener does not call `preventDefault`. Browser SDKs already install global error handlers; enable this adapter only for OpenFL-dispatched errors to avoid duplicate reporting.

`flush`/`close` callbacks are asynchronous on browser/portable backends; native calls can block for the timeout. Java and Cocoa expose void flush APIs: `true` means their flush call returned, not that delivery was confirmed. Native C and JS expose their SDK completion result. Keep the application's event loop running until the close callback completes.

### Obfuscated VM stack traces

For AVM2 or other VM builds with a ProGuard-compatible name mapping, attach the
UUID of the mapping uploaded to the same Sentry project:

```haxe
Sentry.init({
    dsn: "https://public-key@sentry.example.com/42",
    beforeSend: (event, hint) -> {
        sentry.integrations.Proguard.apply(event, "1a876fc1-6ef9-4b93-9f35-11784da018ef");
        return event;
    }
});
```

Generate a different UUID for each build and upload its mapping before shipping,
for example with `sentry-cli upload-proguard --uuid <UUID> mapping.txt`. Mapping
generation belongs to the application's obfuscation pipeline; this library does
not embed mappings or upload credentials. Sentry requires mappings with method
line information. Supply real compiler source positions, not invented ranges.

`Proguard.apply` adds a `proguard` debug image and sets `platform: "java"` on named
VM frames to select Sentry's ProGuard resolver. It preserves the event platform,
runtime context, existing debug images and frames with a native/JavaScript
platform. Flash errors are parsed into AVM2 class and method names, including
Unicode identifiers and constructor frames. Source lines are retained when the
runtime provides them. This adapter resolves structured stack frames; it does
not rewrite arbitrary messages or breadcrumbs, recover stripped information, or
create a blocked-thread stack for synthetic hang reports.

### Flash / AIR hang detection

`FlashHangMonitor` is opt-in and watches the **main event loop**, not rendered FPS. It reports a synthetic `ApplicationHang` with the last filtered scope, breadcrumbs and game context. It cannot extract the blocked thread's stack trace, recover the application, or identify a GPU/driver failure from a missing heartbeat.

| Mode | What it can report | Requirement |
| --- | --- | --- |
| `worker` | Stages a missing heartbeat in memory; sends one event after recovery | Separate embedded worker SWF; Flash 11.4+ and `Worker.isSupported` |
| `recovery` | A delayed callback after the main thread recovers | Works without Worker, including Flash 11.1 |
| `external` | Persists a pending hang outside the runtime; sends once on recovery, or on the next launch after termination | Separately launched watchdog process and loopback IPC |

Build the small, independent worker **from the sentry-haxe repository root**:

```sh
mkdir -p build
haxe tools/build-hang-worker.hxml
```

Embed that SWF into your application's Haxe build (use an absolute path when building another project):

```text
-resource /absolute/path/to/sentry-haxe/build/sentry-hang-worker.swf@sentry-hang-worker
```

Lime/OpenFL projects can build and embed it automatically with `<haxeflag name="--macro" value="sentry.internal.Build.embedHangWorker()" if="flash" />`, or use `<haxeflag name="-resource" value="/absolute/path/to/sentry-hang-worker.swf@sentry-hang-worker" if="flash" />` for an already built helper. Rebuild the helper when updating the library. Do not use the game's entire SWF as the worker. Alternatively pass its `haxe.io.Bytes` as `workerBytes`.

```haxe
#if flash
// After Sentry.init, before starting expensive game loading:
var hangs = sentry.integrations.FlashHangMonitor.install(stage, {
    thresholdMs: 5000,
    heartbeatIntervalMs: 500,
    cooldownMs: 60000,
    pauseWhenInactive: true
});
// hangs.mode: "worker", "recovery", "external", or "stopped".
// Worker/IPC startup is asynchronous; mode initially reads "recovery".
// During intentional pauses/debugging:
hangs.pause();
hangs.resume();
// Before unloading this SWF, or automatically as part of Sentry.close:
hangs.stop(() -> trace("Hang worker stopped"));
#end
```

Defaults suppress background/inactive periods and start at most one hang episode per minute. Each episode produces one finalized event; sampling is decided once for the episode, and cooldown does not discard its recovery. The independent observer discards backward clock changes and gaps of at least the threshold in **its own loop**, then grants a new threshold-length grace period. Shorter scheduling or sleep gaps cannot be identified reliably from heartbeats alone. Recovery mode ignores gaps over `maxRecoveryGapMs` (default 60 seconds) as possible sleep; it cannot reliably distinguish shorter sleep/clock changes from a main-thread block when the runtime emits no lifecycle events. A continuously running Worker/external observer can measure longer hangs without this recovery-only limit. Call `pause` before intentionally suspending execution and `resume` afterwards. If installing into an already-inactive app, pass `initiallyPaused: true` and resume on activation.

The reporting lifecycle follows [Cocoa App Hang V2](https://github.com/getsentry/sentry-cocoa/blob/8.56.2/Sources/Sentry/SentryANRTrackingIntegration.m#L150-L270): **detect, retain locally, then send one finalized event**. It does not send an ongoing event followed by a server-side update or a second recovery event.

- At the threshold, retain the pre-hang snapshot and assign an event ID and detection timestamp. No HTTP event is sent yet.
- If an active heartbeat resumes, send that event once at `error` level with `hang.status: recovered`, `recovered: true`, `duration_ms`, and estimated `duration_min_ms` / `duration_max_ms`. The exception message includes the estimated interval. The original ID, detection time, scope and breadcrumbs remain intact.
- With the external watchdog's disk cache and process tracking configured, a pending hang survives application termination. The next helper launch reports it at `fatal` level if the monitored process has exited. `duration_is_lower_bound: true` and a null upper bound indicate that the exact end was not observed. Time spent waiting for relaunch is never added to the duration.
- Without proof of process termination, an abandoned cached hang is `unresolved` at `error` level, not a claimed crash or recovery. A still-running application/helper instance's cache is not consumed by another instance.

The duration is an observed heartbeat gap, not an exact blocked-thread measurement; `heartbeat_interval_ms` exposes the cadence (500 ms by default), with additional scheduling/IPC latency. Recovery estimates allow up to two heartbeat intervals between the last healthy pulse, actual blockage and first resumed pulse. These are sampling estimates, not guaranteed wall-clock bounds. Recovery means a fresh main-loop heartbeat, not a guarantee that every subsystem is healthy. Pausing, becoming inactive, revoking a snapshot, detected observer clock/poll discontinuities and clean stop discard pending observations. IPC loss alone cannot create a new hang or establish process death.

Worker and recovery-only modes cannot observe their own process's death; their pending state is memory-only. Use the external desktop watchdog for persistent next-launch reporting. This implementation does not capture a native blocked-thread stack or classify partially blocked rendering like Cocoa's frame tracker.

Snapshots pass through `beforeSend` on the main thread **each heartbeat**, with `hint.hangSnapshot == true`. Keep that branch fast and side-effect-free. Returning null or throwing revokes the snapshot. Scope attachments are excluded and snapshots over 256 KiB are discarded. Finalization fills already-present hang fields/tags and the unmodified SDK-generated message; removed fields and custom messages are respected, and scope data is never merged back. A confirmed fatal outcome changes the default error level/mechanism to fatal/unhandled. `contexts.app_hang.snapshot_age_ms` measures snapshot age at detection, not time waiting for a later launch.

Missing/unsupported worker resources or startup failure fall back to recovery mode. A custom `Options.transport` also selects recovery mode, so an isolated worker cannot bypass the application's transport. Worker networking still needs the applicable Flash sandbox policy; an application-sandbox AIR parent grants its packaged helper application privileges. Network failures go to `onError` when the main thread resumes. Monitor health is available through `mode`; it is not a delivery receipt.

`Sentry.close` stops heartbeat production and waits for worker shutdown (bounded by its heartbeat interval plus `shutdownTimeoutMs` and a small scheduling margin), then closes the main client. `flush` covers the main client's queue only. Background reports do not update the main client's `lastEventId`. Worker queues remain memory-only; a process-wide lock or forced termination can prevent their delivery.

### External desktop watchdog

For the Windows “not responding” case affecting the whole runtime, use the separately launched helper. It is also Haxe code, compiled for Node 18+, with **no npm dependencies**:

```sh
mkdir -p build
haxe tools/build-watchdog.hxml
node build/sentry-watchdog.cjs --dsn 'https://public-key@sentry.example.com/42'
```

The helper binds only `127.0.0.1` on an available port and prints a JSON `listening` record containing `port`, a fresh random `token`, and `version: 1`. The launcher reads that line and passes the values to the game:

```haxe
var hangs = sentry.integrations.FlashHangMonitor.install(stage, {
    externalPort: endpoint.port,
    externalToken: endpoint.token
});
```

External mode takes priority over Worker, preventing duplicate reports. It stages the pending incident while the runtime is blocked; the DSN is configured in the helper, and heartbeats contain only filtered snapshots. Never replace the generated token with a constant. A missing connection uses recovery mode and retries every five seconds. The helper tolerates reconnects within its disconnect grace period; after a lost connection it waits for two thresholds, preserves any already-detected pending incident, flushes, and exits. Missing heartbeats or a lost IPC connection are **not proof of a native crash**. A clean `hangs.stop` / `Sentry.close` sends a stop message, preventing a shutdown from being mistaken for a hang. A helper that never receives a connection/initial heartbeat exits after one minute.

Use `--cache-dir /path/to/application-data/hangs` for durable hang state, plus `--watch-parent` when the helper is launched directly by the application, or `--parent-pid <application-pid>` for a separate launcher. The example derives the directory from AIR's `File.applicationStorageDirectory` and enables parent-process tracking automatically. Without a cache directory, only recovered hangs can be delivered; without a monitored PID, stale pending records cannot be classified as fatal.

The cache is partitioned by a SHA-256 of the public DSN, uses private directory/file permissions (0700/0600 where supported), and bounds storage to 32 records per project; records older than seven days are discarded during cache recovery. Pending snapshots are written atomically. After recovery or next-launch classification, the finalized event stays cached until HTTP success; a later launch retries the same event ID and timestamp. A rename claims a record during replay, preventing concurrent helpers from uploading it together. The files contain the application's filtered event data. Filesystem failures are diagnostic and fall back to memory; forced termination before a successful disk write can still lose the incident.

`examples/AirWatchdogLauncher.hx` shows `NativeProcess` startup, stdout handshake parsing and stderr draining. Keep the launcher object alive, initialize ordinary/Worker monitoring first, and replace the monitor in its `onReady` callback. The haxelib contains a packaging script that downloads a pinned Node runtime, checks the official SHA-256 digest, compiles the helper and includes both licenses. The runtime binaries are generated build outputs, not committed library files. Use `python3 tools/package-watchdog.py --platform windows --output /path/to/app/watchdog` or `--platform macos` (both ARM64 and x64). `--verify` checks an existing staging directory. The manifest hashes describe files before platform code signing. AIR's launcher needs the `extendedDesktop` profile and native packaging to start a process. Hosted browser SWFs would additionally need a socket-policy service; this helper intentionally does not provide one and is intended for AIR desktop or a trusted desktop wrapper.

Use `--output-dir /path/to/reports` to also retain `.envelope` files locally, or add `--no-send` for an offline diagnostic run. These files can contain the filtered user/game context; the helper does not replay or rotate them. This optional envelope archive is separate from `--cache-dir`; only the hang journal supports automatic next-launch replay. It does not collect minidumps, kill/restart the application, or upload debug symbols.

## Verification

```sh
mkdir -p build
haxe tests/tests.hxml
haxe -cp src -cp tests -main TestMain -js build/tests.js
node build/tests.js
haxe -cp src -cp tests -main TestMain -swf build/tests.swf -swf-version 32
haxe -cp src -cp tests -main TestMain -swf build/tests-air.swf -swf-version 32 -D air
```

The tests use an in-memory transport and never send to a live Sentry project. `BrowserTest`, `tests/java/BridgeIntegrationTest.java` and `NativeTest` also exercise real SDK adapters using in-memory capture. See `tests/README.md` for commands and the distinction between execution and compile-only coverage.

Hang detection adds deterministic state-machine/privacy tests, a real loopback watchdog test, and desktop AIR fixtures that deliberately block their own main thread. The AIR fixtures also suspend **their own test process** to verify a single report after recovery, and terminate it to verify fatal reporting on the next launch. They cover pause, disposal, redaction and replay prevention after successful delivery. Run these only in a development environment; see `tests/README.md`.

## Upstream references

- [Sentry JavaScript](https://github.com/getsentry/sentry-javascript)
- [Sentry Cocoa](https://github.com/getsentry/sentry-cocoa)
- [Sentry Java / Android](https://github.com/getsentry/sentry-java)
- [Sentry Native](https://github.com/getsentry/sentry-native)
- [Envelope protocol](https://develop.sentry.dev/sdk/envelopes/) and [rate limiting](https://develop.sentry.dev/sdk/expected-features/rate-limiting/)
- [AIR Worker](https://airsdk.dev/reference/actionscript/3.0/flash/system/Worker.html), [worker sandbox privileges](https://airsdk.dev/reference/actionscript/3.0/flash/system/WorkerDomain.html), and [NativeProcess desktop packaging](https://airsdk.dev/reference/actionscript/3.0/flash/desktop/NativeProcess.html)

MIT-licensed Haxe library. Upstream SDKs retain their own licenses. This project is not an official Sentry SDK.
