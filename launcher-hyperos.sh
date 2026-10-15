#!/bin/sh
install_home=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$install_home/Applications/AndroidUnlockHyperOSHelper.app/Contents/MacOS/android-unlock" "$@"
