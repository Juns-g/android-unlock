# ColorOS six-digit PIN support

The supported shape is the observed Find / Android 16 SystemUI six-digit PIN UI with the Chinese accessibility description `密码栏，已输入 N 个值，共 6 个值`. Other PIN lengths, languages, passwords, patterns and first unlocks after reboot are not supported by this profile.

## Verification boundary

The 2026-10-15 preparation-only device diagnostic reached `ready` with `focus_identity_verified`, `hierarchy_xml_parsed`, a verified empty six-digit target, and a locked secure user 0. It did not call the credential reader or send any digit. The ordinary system authentication request showed a biometric invitation; the verified reveal button then exposed the actual keypad.

Later on 2026-10-15, after the owner enrolled the exact transport, the frozen helper built from `6455891fe482e62f00e669bcbfac83b4bb2f9d57` completed one full physical PIN unlock over wireless ADB. The phone was placed screen-down for this test. Read-only checks first confirmed a black, locked, secure user-0 start. A fresh authorized helper process then returned:

- `result=unlocked_confirmed`, exit 0, `submitted=true`;
- noninteractive Keychain `stage=read_success`, `osStatus=0`;
- `actionsAttempted=6`, `adbSucceeded=6`;
- wake and authentication-page preparation performed, followed by `lockState=unlocked`.

A separate helper `status` and direct keyguard-policy read both confirmed online / secure / user 0 / awake / unlocked, with `showing=false`, `mIsShowing=false` and `mInputRestricted=false`. The installed signature and executable were verified unchanged after enrollment; this documentation update does not rebuild or replace that enrolled App. No PIN, digit sequence, raw hierarchy, device serial or Keychain contents are included here.

An earlier wake-only attempt observed the phone become unlocked before any credential read or digit input. Its original receipt was `wake_unconfirmed_no_retry` / exit 3; it is not counted as PIN acceptance. The cause of that earlier transition was not independently established. The full PIN test occurred only after the owner changed the physical conditions and explicitly authorized another attempt.

The existing 582-check synthetic suite covers parsing, preparation gates, per-digit count progression, six-digit length, no Enter dispatch, stopped partial input and rejection paths. The separate physical result establishes one successful fresh-process unlock for this enrolled App and observed UI. It does not establish indefinite Keychain permission, compatibility with other firmware/locales or enrollment of a newly rebuilt signature.

## Narrow compatibility changes

- Preserve an existing display scope only across the exact ColorOS `mIsDensityForced=true` or `mIsDensityForced=false` line. Unknown outdented sections, missing scopes, display conflicts and ambiguous windows remain rejected.
- Recognize the observed lockscreen cover from its SystemUI package, exact resource IDs, classes, ancestry and bounds. A separate exact hierarchy identifies the optional reveal button; overlapping clickable controls are rejected. The observed `scrim_in_front` dismiss-background is accepted only as a unique full-root `android.view.View` before the bouncer, without focus or editable content. Unknown, relocated, duplicated or reshaped overlapping controls remain rejected.
- Allow at most one system authentication request and one verified, nonsecret reveal-button touch. Observe the same secure device, user, focus and window again before the second action. This stage never reads credentials or inputs digits.
- Bind the six-digit target to `oplusos_kgd_security_pin_six_view`, `colorSimpleLock` and `pinColorNumericKeyboard`. The field's own virtual child provides an explicit entered count; each digit is an independently labelled virtual Button inside the keyboard.
- Reject malformed or ambiguous counts, foreign packages, extra focus, missing/duplicate digits, invalid ancestry, overlapping controls and an initially nonempty field. Each digit uses fresh verified geometry and must be followed by the expected count. Six digits auto-submit; the helper never sends Enter into a newly unlocked app.
- Keep the existing SystemUI process/UID/window ownership, default display, collector hash, post-UI state/freshness and credential handling. The existing mDNS-space parsing fix is retained because a duplicate transport name must not invalidate the complete inventory.

## Owner preparation and acceptance

1. Keep a backup of the previous installed App and launcher when replacing the helper. A new ad-hoc signature does not inherit the previous helper's Keychain grant.
2. With this exact phone awake and manually unlocked, the local owner runs `android-unlock setup --local-user --serial SERIAL` and enters the PIN only in the native masked field. Agents do not invoke enrollment or request the PIN. Existing credentials for other devices are not a substitute.
3. After the owner confirms preparation, use the installed helper's normal `devices`, `status` and dry-run sequence. An ordinary user-requested unlock permits one authorized attempt. Stop on refusal, ambiguity, partial input or an unconfirmed outcome; never clear or replay the PIN.
4. Confirm `unlocked_confirmed` with a fresh same-device/user keyguard observation. A `ready` result, successful ADB command, synthesized input test or saved Keychain item alone does not meet this acceptance.

Credential accounts currently bind the exact ADB serial string. Wireless port/name changes can therefore require owner preparation for the new transport; this branch does not migrate credentials or broaden their identity binding.
