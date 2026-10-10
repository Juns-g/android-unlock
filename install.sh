#!/bin/sh
set -eu
usage() { printf '%s\n' 'Usage: sh install.sh /absolute/build [--replace] [--stage /absolute/stage]'; exit 64; }
[ "$#" -ge 1 ] || usage
build=$1; shift
case "$build" in /*) ;; *) usage ;; esac
target_root=$HOME; replace=false
case "$#" in
  0) ;;
  1) [ "$1" = --replace ] || usage; replace=true ;;
  2) [ "$1" = --stage ] || usage; case "$2" in /*) target_root=$2 ;; *) usage ;; esac ;;
  3) [ "$1" = --replace ] && [ "$2" = --stage ] || usage; case "$3" in /*) target_root=$3 ;; *) usage ;; esac; replace=true ;;
  *) usage ;;
esac
[ "$(id -u)" -ne 0 ] || { printf '%s\n' 'Run as the local user, without sudo.' >&2; exit 77; }
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_app="$build/AndroidUnlockHelper.app"
codesign --verify --deep --strict "$source_app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" = page.juns.AndroidUnlockHelper ] || exit 65
[ -f "$source_app/Contents/MacOS/android-unlock" ] || exit 65
app="$target_root/Applications/AndroidUnlockHelper.app"
launcher="$target_root/.local/bin/android-unlock"
if [ -e "$app" ] || [ -L "$app" ] || [ -e "$launcher" ] || [ -L "$launcher" ]; then
  [ "$replace" = true ] || { printf '%s\n' 'Existing app or launcher: refused. Use --replace only for an intended update.' >&2; exit 73; }
fi
umask 077
mkdir -p "$target_root/Applications" "$target_root/.local/bin"
if [ "$replace" = true ]; then
  backup=$(mktemp -d "$target_root/Applications/.android-unlock-backup.XXXXXX")
  if [ -e "$app" ] || [ -L "$app" ]; then mv "$app" "$backup/AndroidUnlockHelper.app"; fi
  if [ -e "$launcher" ] || [ -L "$launcher" ]; then mv "$launcher" "$backup/android-unlock"; fi
  printf 'Previous files preserved in %s\n' "$backup"
fi
ditto "$source_app" "$app"
codesign --verify --deep --strict "$app"
cp "$source_dir/launcher.sh" "$launcher"
chmod 700 "$launcher"
printf '%s\n' 'Installed. Enrollment is a separate human-only action; no device or Keychain operation was run.'
