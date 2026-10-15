#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { [ "$#" -eq 3 ] && [ "$2" = --adb ]; } || { printf '%s\n' 'Usage: sh build.sh /absolute/output [--adb /absolute/official/adb]'; exit 64; }
case "$1" in /*) ;; *) exit 64 ;; esac
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -eq 3 ]; then adb_candidate=$3; else adb_candidate=$(command -v adb) || { printf '%s\n' 'Install official Android platform-tools or pass --adb.' >&2; exit 69; }; fi
app_dir="$1/AndroidUnlockHelper.app"
collector_sha=d12c6c593024940bd75aba01568d6dd02184ea032bb388f9418de00eeb01f9dc
collector_source="$source_dir/fast-reader/collector.jar"
[ "$(/usr/bin/shasum -a 256 "$collector_source" | /usr/bin/cut -d ' ' -f 1)" = "$collector_sha" ] || exit 65
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
swift "$source_dir/BuildConfig.swift" "$adb_candidate" "$app_dir/Contents/Info.plist"
cp "$collector_source" "$app_dir/Contents/Resources/fast-reader.jar"
[ "$(/usr/bin/shasum -a 256 "$app_dir/Contents/Resources/fast-reader.jar" | /usr/bin/cut -d ' ' -f 1)" = "$collector_sha" ] || exit 65
swiftc -O "$source_dir/Policy.swift" "$source_dir/ColorOS.swift" "$source_dir/HyperOSCover.swift" "$source_dir/Native.swift" "$source_dir/NativeProgress.swift" "$source_dir/main.swift" -o "$app_dir/Contents/MacOS/android-unlock"
codesign --force --sign - --identifier page.juns.AndroidUnlockHelper --timestamp=none "$app_dir"
codesign --verify --deep --strict "$app_dir"
