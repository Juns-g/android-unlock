# android-unlock

[English](README.md) | [简体中文](README.zh-CN.md)

A small macOS CLI and agent [Skill](SKILL.md) for ordinary Android screen authentication using the owner's locally saved numeric PIN. It does not defeat a lockscreen. The native, locally ad-hoc-signed App provides a masked enrollment dialog and a stable Keychain identity; it is not a general GUI product.

## Requirements and limits

- macOS with Swift/Xcode command-line tools, an official Android platform-tools `adb`, and an **already running local ADB server on 127.0.0.1:5037**. A debug switch alone does not establish the phone's RSA trust or an online connection. The helper will not start, restart, replace, or redirect that server. Its pinned client executable may differ from the executable that originally started the shared server; the server/host must also be trusted.
- Explicit exact device serial, primary Android user 0, secure ordinary lockscreen, and Android user already unlocked once since boot. The first unlock after reboot must be performed manually. Password, pattern, biometrics and other users are unsupported.
- A known Vivo six-slot numeric UI was tested on Android 16. A narrow four-digit numeric Meizu 17 / Android 13 / Flyme 10.5.0.0A profile now uses guarded normal touches and source-bound accessibility progress. Strict AOSP PIN parsing also exists; other variants are unverified. No always-on screen is needed: an authorized attempt may wake once and request the system authentication UI once.

This branch also implements the observed ColorOS six-digit UI with its Chinese accessibility count. Its preparation-only Find test reached a verified empty keypad without reading credentials or entering digits; **actual PIN entry and a confirmed physical unlock remain pending**. ColorOS preparation may request the system authentication page once and then tap one independently verified `showPasswordButton` before the keypad appears. See [ColorOS validation and owner preparation](docs/coloros-validation.md).

On 2026-10-11 the source baseline completed one fresh-process, noninteractive Keychain unlock from a black locked screen, followed by an independent unlocked status. A later requested attempt stopped before credential read/input when a window could not be verified; an unrelated later unlocked observation had unknown cause. On 2026-10-12, the frozen Flyme source baseline achieved four independently verified physical unlocks (three black-screen starts, then one awake/locked start after restoration), with successful ordinary new-process noninteractive Keychain reads. Its CLI still exits 3 with `flyme_progress_missing_ack` after the last touch: this is a known terminal-receipt false negative, not a successful CLI receipt. Main preserves that tested baseline; an optional terminal-confirmation patch is offline-checked but not live-accepted. Read the [validation and owner-only follow-up](docs/flyme-validation.md) before using Flyme. This public checkout can be built and checked offline; a newly rebuilt signature has not been enrolled or live-tested and does not inherit the local baseline’s Keychain grant. A safe stop is expected whenever current identity, focus, geometry or timing cannot be established.

## Build and install

**Latest Vivo acceptance (2026-10-13):** restoring the original locally approved Vivo bundle completed one ordinary black/locked → fresh-process noninteractive Keychain read → `unlocked_confirmed/exit0` flow in 36.509 seconds, followed by independent secure/user0/unlocked status. No new owner approval or PIN change was needed. [Latest validation and version distinction](docs/vivo-validation.md) explains why this local result is not a live acceptance of a newly rebuilt public signature, nor resolution of Flyme's known CLI false negative. This update changes documentation only, not the working installed App.

From this checkout:

```sh
sh build.sh "$PWD/build"
# SDK not on build-time PATH: sh build.sh "$PWD/build" --adb /absolute/platform-tools/adb
sh check.sh "$PWD/build"
sh install.sh "$PWD/build"
"$HOME/.local/bin/android-unlock" help
```

The build resolves ADB symlinks once, verifies an executable real file owned by the current user or root and not group/world writable, and pins its absolute path in the signed bundle. Runtime never searches PATH or reads an ADB override. Moving/updating to a different client path requires rebuilding. There is no official signing or notarization claim.

Install targets are `~/Applications/AndroidUnlockHelper.app` and `~/.local/bin/android-unlock`. The launcher executes the real bundle executable, not a binary symlink. If either the app or the launcher already exists, installation is refused by default. For an intended update, `sh install.sh "$PWD/build" --replace` preserves old files in a local backup directory before replacement. An ad-hoc update can change Keychain trust; it does not migrate or grant permissions.

For a safe installation smoke test:

```sh
sh install.sh "$PWD/build" --stage "$PWD/build/stage"
"$PWD/build/stage/.local/bin/android-unlock" help
```

Staging copies and verifies the actual signed bundle, but **does not make that path eligible for enrollment, existing-item authorization or an authorized unlock**. Use a new stage directory; existing targets are refused. An explicit `--replace --stage /absolute/stage` is available for a staged replacement smoke test. The installer never runs ADB, setup, authorization or any device action.

## One-time human preparation

The read-only collector is code, not an APK. A human operator explicitly deploys the bundled, hash-pinned JAR to the already authorized device; the helper never uploads it automatically:

```sh
adb -s SERIAL push fast-reader/collector.jar /data/local/tmp/page.juns.android-unlock-128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def.jar
adb -s SERIAL shell toybox sha256sum /data/local/tmp/page.juns.android-unlock-128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def.jar
```

Both local and device digests must equal `128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def`. Missing/mismatched code blocks the helper. Source and compile-only API stubs are included. To rebuild, supply your JDK and an official Google R8/D8 JAR: `sh fast-reader/build.sh /absolute/output /absolute/r8.jar`. Rebuilds can change archive bytes; replacing the sealed resource requires an intentional audited hash update, not disabling verification. The DEX contains only original `FastHierarchy`, `FlymeProgressSession` and its generated listener class; stubs are never runtime implementations. See [source/license notes](THIRD_PARTY_NOTICES.md).

With the phone manually unlocked, awake and secure, the **local human** runs:

```sh
"$HOME/.local/bin/android-unlock" setup --local-user --serial SERIAL
```

Enter the PIN only in the native masked field. It is stored in this helper's own local generic Keychain item, bound to macOS UID, serial and Android user 0. After an update, a human can run `authorize-existing --local-user --serial SERIAL` and decide in the macOS-owned Keychain dialog. It reads the existing item without rewriting its PIN/ACL. A successful interactive read followed by one noninteractive read proves only **same-process** access; it does not promise a persistent or next-process grant. Agents must not invoke these human enrollment/authorization flows or request PINs in chat.

## Operation

```sh
android-unlock devices
android-unlock status --serial SERIAL
android-unlock preflight --serial SERIAL
android-unlock unlock --dry-run --serial SERIAL
# Only with authorization for this exact phone:
android-unlock unlock --authorize --serial SERIAL
```

Read-only commands never wake, present, input or query credentials. Authorized unlock is one bounded preparation and at most one PIN attempt, with no clear, append, retry or automatic relock. It uses fresh full SystemUI package/process/window/display/user/secure checks, a verified empty field, explicit each-digit progress and a two-second post-UI evidence limit. Filled Vivo prefix slots may disappear only as justified by the explicit count; unfilled slots, all backgrounds and the complete keyboard remain required. Its one nonsecret placeholder activity uses the immediately preceding full proof only while still fresh. Vivo auto-submit never sends Enter into a newly unlocked app.

Receipts contain fixed nonsecret metadata. `unlocked_confirmed` requires independent same-device/user keyguard readback. `already_unlocked` consumes no PIN. A zero command exit alone is not authentication or GUI/business success. Stop on blocked, changed state, refusal, timeout or partial input; obtain new evidence rather than replaying. Exit codes: 0 observed/ready/confirmed, 2 blocked, 3 attempted but unconfirmed, 64 usage.

Hierarchy bytes travel through an anonymous stdout pipe and native memory, not UI dump files or logs. The collector avoids the framework dumper's private UI logging. Full PINs never enter command arguments, environment, files, receipts or agent context; secret-dependent input uses private non-PTY stdin with output suppressed. Focus verification and dispatch are not atomic, privileged OS/ADB observation can see input, and complete erasure of all OS/framework copies is not guaranteed. Use a trusted Mac, ADB server and Android OS.

中文：先安装并由本人在本机掩码窗口保存 PIN；Agent 只指定准确 serial、只读检查，并在授权后尝试一次。失败或部分输入立即停止。这里验证的是普通锁屏认证，不代表后续 App 操作已获授权。

## License

Original helper, collector and packaging: MIT. The project's self-authored compile-only Android API declarations are separately licensed Apache-2.0; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
