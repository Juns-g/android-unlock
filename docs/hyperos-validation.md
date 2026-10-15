# HyperOS standalone validation

This branch combines the strict HyperOS keypad profile from `1912ed9` with the previously accepted ColorOS code, and provides an optional separately signed HyperOS App so an enrolled default helper can remain unchanged.

The HyperOS profile recognizes the observed `keyguard_pin_view` / `pin_container` ancestry, an empty or bullet-only `PasswordTextView` `pinEntry`, ten distinct resource-ID digit targets, and matching delete/emergency geometry. It uses each digit's freshly observed center and requires the expected entered count before each action. It neither clears an existing prefix nor dispatches Enter after the final digit. Unknown identity, focus, state, geometry or progress stops the attempt.

The compile-time `HYPEROS_STANDALONE` variant fixes its bundle identifier to `page.juns.AndroidUnlockHyperOSHelper` and its only eligible credential/unlock path to `~/Applications/AndroidUnlockHyperOSHelper.app/Contents/MacOS/android-unlock`. It does not accept a runtime path override. The default identifier/path and shared exact UID/serial/user Keychain account remain unchanged. A new signature still needs the owner's native authorization for an existing PIN item.

Both build variants pass the combined offline checks, including existing ColorOS, Vivo, Flyme, AOSP and HyperOS fixtures. A staged standalone installation verifies its separate bundle, launcher and collector while retaining the default enrolled binary. These facts alone do not establish fresh-process Keychain access or physical HyperOS PIN unlock.

Real-device acceptance is pending. Initial preparation-only observations found that the phone could return to dozing immediately after a wake request, with the power service reporting an application sleep reason. No credential or PIN input was used during this investigation, and no biometric, device security or power configuration was changed. The normal SystemUI identity checks and wake-only event remain enforced.

Further inspection identified a focused `com.miui.aod:id/shortcut_view_left` on the ordinary lockscreen. Generic parsing correctly rejects an unknown focused clickable control; sending Space to that control is inappropriate. A separate cover verifier now requires the exact SystemUI root/header and AOD shortcut ancestry, classes, flags, unique nodes and contained nonoverlapping geometry. It permits focus only on that precise shortcut, rejects editable/password content and credential pages, and requests the system authentication page without touching or activating the shortcut. Generic AOSP/Vivo/Flyme/ColorOS parsing is unchanged.

The revised preparation-only device test and built candidate dry-run reached `ready` / `hyperos_pin` with count 0, verified SystemUI identity and a locked secure user 0. Both build variants pass 653 synthetic checks. This remains distinct from a successful Keychain read and physical PIN unlock. During one diagnostic, an existing periodic keepalive job was temporarily paused to isolate concurrent wake events and restored afterward; it was not reconfigured. The installed default helper remains unchanged.

For owner handoff, keep the phone unfolded and manually unlocked, then personally run `android-unlock-hyperos authorize-existing --local-user --serial SERIAL` for the existing item. A same-process authorization receipt is not proof of persistent access. The final acceptance requires a new authorized process, one complete guarded PIN attempt, and an independent same-device/user keyguard readback.

## Empty-field activity before input

After owner enrollment, a fresh process successfully read the Keychain item but the previous version stopped with `state_changed_before_input`, without sending a digit. A no-credential reproduction showed matching empty PIN targets around 6 and 9 seconds, then screen-off during the pre-input observation around 12 seconds. The observed lockscreen activity timeout was 10 seconds; it is separate from the configured general screen timeout.

HyperOS now uses the existing guarded nonsecret activity mechanism for its verified empty `PasswordTextView` bounds. The touch is allowed only with the original full SystemUI/device/user/display proof, a zero entered count, a fresh post-UI check within two seconds, and a point contained in the field and outside every digit key. A full observation follows it before any PIN input. No timeout setting, credential source, input count or retry rule is relaxed; nonempty or stale fields are rejected. The original Vivo activity path is retained.

Both build variants pass 665 synthetic checks. The revised no-credential device diagnostic performed one verified empty-field touch and retained `ready`, count 0 and the same target through the pre-input and first-digit-readiness observations at approximately 15 and 19 seconds. This proves the nonsecret preparation change; final PIN unlock acceptance for the updated signed App remains pending.

## Latest physical input attempt: stopped after one unacknowledged action

After the owner authorized the frozen App built from `d7757fc0165b49ac703d23637d7383bd16d07975`, a new process successfully read the Keychain item noninteractively (`read_success`, status 0). Preparation and the verified empty-field activity succeeded. One digit-dependent touch was dispatched with a successful ADB command result, but the next fresh observation still reported count 0. The helper returned `partial_input_aborted_no_retry` / exit 3 and sent no further digits. The elapsed authorized command time was 24.522 seconds.

The original partial-input receipt is preserved: `actionsAttempted=1`, `adbSucceeded=1`, `observedEnteredCount=0`, and `submitted=true`. Here `submitted` records that the input phase began; it is not proof that a complete PIN was submitted. An ADB exit status is likewise not proof that the device accepted a digit. No clear, append or retry followed. An independent read still found the phone locked, and the temporarily paused keepalive job was restored.

Read-only diagnostics found the standard shell `INJECT_EVENTS` permission granted, with no relevant denial category in the scoped input-service logs. An extra OEM input-security requirement is an investigation hypothesis, not a confirmed cause. The owner was asked to check the device's additional USB-debugging security setting. Actual unlock acceptance remains incomplete; do not retry solely because the observed count was zero.
