#!/bin/sh
set -eu
[ "$#" -eq 2 ] || { printf '%s\n' 'Usage: build.sh /absolute/output /absolute/r8.jar'; exit 64; }
case "$1:$2" in /*:/*) ;; *) exit 64 ;; esac
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$1/stub-classes" "$1/classes" "$1/dex"
javac --release 8 -d "$1/stub-classes" "$src/stubs/com/android/uiautomator/core/UiDevice.java" "$src/stubs/com/android/uiautomator/core/UiAutomatorBridge.java" "$src/stubs/com/android/uiautomator/testrunner/UiAutomatorTestCase.java" "$src/stubs/android/graphics/Rect.java" "$src/stubs/android/view/accessibility/AccessibilityNodeInfo.java"
javac --release 8 -cp "$1/stub-classes" -d "$1/classes" "$src/src/page/juns/androidunlock/FastHierarchy.java"
java -cp "$2" com.android.tools.r8.D8 --min-api 26 --lib "$1/stub-classes" --output "$1/dex" "$1/classes/page/juns/androidunlock/FastHierarchy.class"
jar --create --file "$1/collector.jar" -C "$1/dex" classes.dex
