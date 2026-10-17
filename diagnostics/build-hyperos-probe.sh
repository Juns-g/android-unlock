#!/bin/sh
set -eu
[ "$#" -eq 2 ] || exit 64
case "$1:$2" in /*:/*) ;; *) exit 64 ;; esac
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$1/stub-classes" "$1/classes" "$1/dex"
find "$source_dir/fast-reader/stubs" -name '*.java' -print > "$1/stub-sources.txt"
javac --release 8 -d "$1/stub-classes" @"$1/stub-sources.txt"
javac --release 8 -cp "$1/stub-classes" -d "$1/classes" "$source_dir/diagnostics/HyperOSProgressProbe.java"
java -cp "$2" com.android.tools.r8.D8 --min-api 26 --lib "$1/stub-classes" --output "$1/dex" "$1/classes/page/juns/androidunlock/"*.class
jar --create --date=2026-01-01T00:00:00Z --file "$1/hyperos-progress-probe.jar" -C "$1/dex" classes.dex
