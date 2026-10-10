# Embedded code and API provenance

`FastHierarchy.java` is an original bounded, read-only node walker. Its bundled `collector.jar` contains only that custom class in `classes.dex`, plus standard JAR metadata. It contains no framework dumper, Android stub implementations, Appium, smali or other research project code. The original collector and helper are MIT-licensed.

`fast-reader/stubs/` contains minimal compile-only declarations authored for this project by Juns-g (2026), modeling standard Android APIs. They contain no copied upstream implementation or headers and are separately licensed under [Apache License 2.0](fast-reader/stubs/LICENSE). These classes are excluded from the DEX and never shipped as replacement platform code. The actual Android runtime and SDK tools are not distributed here. The following URLs are API references, not claims of copied-code provenance:

- [UiDevice](https://android.googlesource.com/platform/frameworks/uiautomator/+/refs/heads/main/src/com/android/uiautomator/core/UiDevice.java): preserve the literal legacy spelling `setCompressedLayoutHeirarchy`. The collector reflects only the runner's own `getAutomatorBridge` accessor; it makes no hidden-API exemption.
- [UiAutomatorBridge](https://android.googlesource.com/platform/frameworks/uiautomator/+/refs/heads/main/src/com/android/uiautomator/core/UiAutomatorBridge.java).
- [UiAutomatorTestCase](https://android.googlesource.com/platform/frameworks/uiautomator/+/refs/heads/main/src/com/android/uiautomator/testrunner/UiAutomatorTestCase.java).
- [AccessibilityNodeInfo](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/view/accessibility/AccessibilityNodeInfo.java) and [Rect](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/Rect.java).

The UIAutomator links are moving source branches, not invented pinned commits. Runtime ABI/accessibility support remains device-dependent and fails closed. R8/D8, the JDK, Swift and platform-tools are user-supplied build/runtime tools, not vendored here. No official Android, Apple, signing or notarization endorsement is claimed.
