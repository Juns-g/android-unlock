# HyperOS standalone validation

This branch combines the strict HyperOS keypad profile from `1912ed9` with the previously accepted ColorOS code, and provides an optional separately signed HyperOS App so an enrolled default helper can remain unchanged.

The HyperOS profile recognizes the observed `keyguard_pin_view` / `pin_container` ancestry, an empty or bullet-only `PasswordTextView` `pinEntry`, ten distinct resource-ID digit targets, and matching delete/emergency geometry. It uses each digit's freshly observed center and requires the expected entered count before each action. It neither clears an existing prefix nor dispatches Enter after the final digit. Unknown identity, focus, state, geometry or progress stops the attempt.

The compile-time `HYPEROS_STANDALONE` variant fixes its bundle identifier to `page.juns.AndroidUnlockHyperOSHelper` and its only eligible credential/unlock path to `~/Applications/AndroidUnlockHyperOSHelper.app/Contents/MacOS/android-unlock`. It does not accept a runtime path override. The default identifier/path and shared exact UID/serial/user Keychain account remain unchanged. A new signature still needs the owner's native authorization for an existing PIN item.

Both build variants pass the combined offline checks, including existing ColorOS, Vivo, Flyme, AOSP and HyperOS fixtures. A staged standalone installation verifies its separate bundle, launcher and collector while retaining the default enrolled binary. These facts alone do not establish fresh-process Keychain access or physical HyperOS PIN unlock.

Real-device acceptance is pending. Initial preparation-only observations found that the phone could return to dozing immediately after a wake request, with the power service reporting an application sleep reason. No credential or PIN input was used during this investigation, and no biometric, device security or power configuration was changed. The normal SystemUI identity checks and wake-only event remain enforced.

For owner handoff, keep the phone unfolded and manually unlocked, then personally run `android-unlock-hyperos authorize-existing --local-user --serial SERIAL` for the existing item. A same-process authorization receipt is not proof of persistent access. The final acceptance requires a new authorized process, one complete guarded PIN attempt, and an independent same-device/user keyguard readback.
