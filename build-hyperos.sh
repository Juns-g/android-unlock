#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { [ "$#" -eq 3 ] && [ "$2" = --adb ]; } || { printf '%s\n' 'Usage: sh build-hyperos.sh /absolute/output [--adb /absolute/official/adb]'; exit 64; }
case "$1" in /*) ;; *) exit 64 ;; esac
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -eq 3 ]; then adb_candidate=$3; else adb_candidate=$(command -v adb) || { printf '%s\n' 'Install official Android platform-tools or pass --adb.' >&2; exit 69; }; fi
app_dir="$1/AndroidUnlockHyperOSHelper.app"
collector_sha=128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def
collector_source="$source_dir/fast-reader/collector.jar"
[ "$(/usr/bin/shasum -a 256 "$collector_source" | /usr/bin/cut -d ' ' -f 1)" = "$collector_sha" ] || exit 65
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
swift -D HYPEROS_STANDALONE "$source_dir/BuildConfig.swift" "$adb_candidate" "$app_dir/Contents/Info.plist"
cp "$collector_source" "$app_dir/Contents/Resources/fast-reader.jar"
[ "$(/usr/bin/shasum -a 256 "$app_dir/Contents/Resources/fast-reader.jar" | /usr/bin/cut -d ' ' -f 1)" = "$collector_sha" ] || exit 65
swiftc -D HYPEROS_STANDALONE -O "$source_dir/Policy.swift" "$source_dir/ColorOS.swift" "$source_dir/HyperOSCover.swift" "$source_dir/Native.swift" "$source_dir/NativeProgress.swift" "$source_dir/main.swift" -o "$app_dir/Contents/MacOS/android-unlock"
codesign --force --sign - --identifier page.juns.AndroidUnlockHyperOSHelper --timestamp=none "$app_dir"
codesign --verify --deep --strict "$app_dir"
