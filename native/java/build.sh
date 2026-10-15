#!/usr/bin/env sh
set -eu
bridge_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sdk_jar=${1:?Usage: build.sh /path/to/sentry-8.24.0.jar}
mkdir -p "$bridge_dir/build/classes"
javac --release 8 -Xlint:-options -cp "$sdk_jar" -d "$bridge_dir/build/classes" "$bridge_dir/src/io/sentry/haxe/SentryHaxeBridge.java"
jar cf "$bridge_dir/build/sentry-haxe-bridge.jar" -C "$bridge_dir/build/classes" .
