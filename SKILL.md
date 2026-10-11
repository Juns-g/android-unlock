---
name: android-unlock
description: Use when checking or unlocking an Android screen.
platforms: [macos]
---

[English](SKILL.md) | [简体中文](SKILL.zh-CN.md)

`SKILL.md` remains the canonical agent-discovery entry; the Chinese companion is a reading reference, not a second registered Skill.

Use the installed local `~/.local/bin/android-unlock` CLI on macOS. Read [README.md](README.md), relative to this Skill checkout, when installation, compatibility, missing collector code or enrollment is in question. If the CLI is absent, stop with that prerequisite; install/enrollment is a separate local-human task.

1. Run `"$HOME/.local/bin/android-unlock" devices`. Select the user's exact serial from the nonsecret list; never choose a write target implicitly.
2. Run `status --serial SERIAL`, then `unlock --dry-run --serial SERIAL` through that same CLI. Treat unknown identity/focus/state or missing prerequisites as blocked. Read-only commands do not wake or read Keychain.
3. With user authorization for this phone's ordinary unlock, run **once**: `"$HOME/.local/bin/android-unlock" unlock --authorize --serial SERIAL`. This includes bounded wake and authentication-page presentation. No screen-always-on prerequisite.
4. Report the fixed JSON result. `unlocked_confirmed` is independently checked; `already_unlocked` is a no-PIN no-op. For blocked, refused, unconfirmed or partial input, stop and report the exact safe category. Do not retry, clear, append or override the credential source.

The local human alone invokes `setup --local-user` or `authorize-existing --local-user` and enters secrets only in native/system UI. Never request, retrieve or pass a PIN via chat, argv, environment, files or alternate tools. Preserve the existing trusted ADB connection, own Keychain item and all helper safety gates. App/business actions after unlocking require their own authorization; unlocking does not perform them.
