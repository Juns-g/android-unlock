# 嵌入代码与 API 来源说明

[English](THIRD_PARTY_NOTICES.md) | [简体中文](THIRD_PARTY_NOTICES.zh-CN.md)

`FastHierarchy.java`是本项目原创、有界且只读的节点遍历器。`FlymeProgressSession.java`是原创的有界会话采集器，仅观察数值无障碍事件元数据及受守卫的层级快照，不读取事件text或beforeText。随附`collector.jar`的`classes.dex`中只有这两个原创类及生成的监听器类，另附标准JAR元数据。它不包含系统框架导出器、Android stub 实现、Appium、smali 或其他研究项目代码。原创采集器和助手采用 MIT 许可证。

`fast-reader/stubs/` 是 Juns-g 于 2026 年为本项目编写的最小编译声明，描述标准 Android API。它们不包含从上游复制的实现或文件头，单独采用 [Apache License 2.0](fast-reader/stubs/LICENSE)。这些类不进入 DEX，也不作为替代平台实现发布。实际 Android 运行时和 SDK 工具不随本仓库分发。以下链接是 API 参考，不表示本仓库复制了对应代码：

- [UiDevice](https://android.googlesource.com/platform/frameworks/uiautomator/+/refs/heads/main/src/com/android/uiautomator/core/UiDevice.java)：保留旧 API 的字面拼写 `setCompressedLayoutHeirarchy`。采集器仅通过反射访问 runner 自己的 `getAutomatorBridge` accessor，不设置 hidden-API 豁免。
- [UiAutomatorBridge](https://android.googlesource.com/platform/frameworks/uiautomator/+/refs/heads/main/src/com/android/uiautomator/core/UiAutomatorBridge.java)。
- [UiAutomatorTestCase](https://android.googlesource.com/platform/frameworks/uiautomator/+/refs/heads/main/src/com/android/uiautomator/testrunner/UiAutomatorTestCase.java)。
- [AccessibilityNodeInfo](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/view/accessibility/AccessibilityNodeInfo.java) 和 [Rect](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/graphics/java/android/graphics/Rect.java)。

UIAutomator 链接指向动态更新的上游源码分支，而非固定 commit。运行时 ABI 和无障碍接口支持仍取决于具体设备；无法验证时拒绝继续。R8/D8、JDK、Swift 和 platform-tools 是用户自行提供的构建或运行工具，不内置于本仓库。本项目不宣称获得 Android、Apple、签名或公证方面的官方认可。

本文件是来源与许可的中文说明，不替代仓库中的许可证法律原文。
