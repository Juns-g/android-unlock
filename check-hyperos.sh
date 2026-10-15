#!/bin/sh
set -eu
[ "$#" -eq 1 ] || exit 64
case "$1" in /*) ;; *) exit 64 ;; esac
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -f "$1/AndroidUnlockHyperOSHelper.app/Contents/Resources/fast-reader.jar" ] || { printf '%s\n' 'Build the app in this same output directory first.' >&2; exit 65; }
mkdir -p "$1"
swiftc -D HYPEROS_STANDALONE "$source_dir/Policy.swift" "$source_dir/ColorOS.swift" "$source_dir/Native.swift" "$source_dir/NativeProgress.swift" "$source_dir/ColorOSChecks.swift" "$source_dir/ColorOSPinChecks.swift" "$source_dir/Checks.swift" -o "$1/checks-hyperos"
"$1/checks-hyperos"
