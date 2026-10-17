---
name: android-unlock
description: Use when checking or unlocking an Android screen.
platforms: [macos]
---

[English](SKILL.md) | [简体中文](SKILL.zh-CN.md)

`SKILL.md` remains the canonical agent-discovery entry; the Chinese companion is a reading reference, not a second registered Skill.

Use the installed local `~/.local/bin/android-unlock` CLI on macOS. Read [README.md](README.md), relative to this Skill checkout, when installation, compatibility, missing collector code or enrollment is in question. If the CLI is not found, stop immediately; installation and enrollment must be completed manually by the user.

For the optional side-by-side HyperOS installation, use the installed `~/.local/bin/android-unlock-hyperos` for the explicitly selected HyperOS phone, substituting that CLI prefix in every step below. Its separate stable bundle is `~/Applications/AndroidUnlockHyperOSHelper.app`; keep an enrolled default helper unchanged. Both variants retain the same exact serial/user credential binding and owner-only enrollment/authorization rules. Never assume the new signed App inherits another App's Keychain permission.

1. Run `"$HOME/.local/bin/android-unlock" devices`. Select the user's exact serial from the nonsecret list; never choose a write target implicitly.
2. Run `status --serial SERIAL`, then `unlock --dry-run --serial SERIAL` through that same CLI. Treat unknown identity/focus/state or missing prerequisites as blocked. Read-only commands do not wake or read Keychain.
3. With user authorization for this phone's ordinary unlock, run **once**: `"$HOME/.local/bin/android-unlock" unlock --authorize --serial SERIAL`. This includes bounded wake and authentication-page presentation. No screen-always-on prerequisite.
4. Report the fixed JSON result. `unlocked_confirmed` is independently checked; `already_unlocked` is a no-PIN no-op. For blocked, refused, unconfirmed or partial input, stop and report the exact safe category. Do not retry, clear, append or override the credential source.

The local human alone invokes `setup --local-user` or `authorize-existing --local-user` and enters secrets only in native/system UI. Never request, retrieve or pass a PIN via chat, argv, environment, files or alternate tools. Do not alter the trusted ADB connection, the helper's Keychain item, or any existing safety checks. App/business actions after unlocking require their own authorization; unlocking does not perform them.


For the exact Flyme four-digit baseline, read [known terminal false negative](docs/flyme-validation.md). A receipt with `pinProfile=flyme_four`, `actionsAttempted=4`, `adbSucceeded=4` and `reason=flyme_progress_missing_ack` is still CLI exit 3: do not rewrite it or retry. Obtain one fresh read-only `status --serial SERIAL` for the same target. If it independently reports observed/online/secure/user0/unlocked, report the physical unlock separately from the CLI error. Locked, unknown, user/identity changes and all earlier progress failures remain stopped. Do not replace an already approved working App merely to polish this receipt; new-signature authorization is owner-only and can be deferred.

For the exact tested HyperOS six-digit baseline, read [physical acceptance and terminal receipt limit](docs/hyperos-validation.md#accepted-physical-unlock-and-terminal-receipt-limit). With `pinProfile=hyperos_pin`, `inputObservation.actionsAttempted=6`, `adbSucceeded=6` and `reason=hyperos_progress_source_unverified`, preserve the original exit 3 and JSON. Obtain one fresh read-only `android-unlock-hyperos status --serial SERIAL`. Only independent observed/online/awake/secure/user0/unlocked confirms physical completion; report the remaining CLI false negative separately. Do not infer the sixth event acknowledgement, retry, clear or append. Other errors, fewer actions, locked/unknown state or identity/user changes remain stopped. Keep the approved working App unchanged; do not demand another enrollment or new-signature approval solely for receipt cleanup.
