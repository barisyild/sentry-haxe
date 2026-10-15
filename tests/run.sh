#!/usr/bin/env sh
set -eu
test_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$test_root"
mkdir -p build
haxe tests/tests.hxml
haxe -cp src -cp tests -main TestMain -js build/tests.js
node build/tests.js
haxe -cp src -cp tests -main HangTest --interp
haxe -cp src -cp tests -main HangTest -js build/hang-tests.js
node build/hang-tests.js
haxe tools/build-hang-worker.hxml
haxe tools/build-watchdog.hxml
haxe -cp src -cp tests -main TestMain -swf build/tests.swf -swf-version 32
haxe -cp src -cp tests -main TestMain -swf build/tests-air.swf -swf-version 32 -D air
haxe -cp src -cp examples -main Main --interp
haxe -cp src -cp examples -main Main --macro 'include("sentry.integrations.FlashHangMonitor")' -swf build/hang-flash.swf -swf-version 11.1
haxe -cp src -cp examples -main Main --macro 'include("sentry.integrations.FlashHangMonitor")' --macro 'include("AirWatchdogLauncher")' -swf build/hang-air.swf -swf-version 32 -D air -resource build/sentry-hang-worker.swf@sentry-hang-worker
