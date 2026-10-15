# android-unlock

[English](README.md) | [简体中文](README.zh-CN.md)

一个小型 macOS CLI 和 Agent [Skill](SKILL.zh-CN.md)，使用设备所有者保存在本机的数字 PIN，完成 Android 普通锁屏的正常认证。它不是破解或绕过锁屏的工具。原生 App 在本机采用 ad-hoc 签名，提供掩码输入的首次配置窗口和稳定的钥匙串身份；它不是通用桌面 GUI 产品。

## 前提与限制

- Mac 需安装 Swift/Xcode 命令行工具、官方 Android platform-tools 中的 `adb`，并且 **`127.0.0.1:5037` 上已有运行中的本地 ADB 服务**。仅开启 USB 调试，不代表手机已信任此 Mac 的 RSA 身份或设备已在线。助手不会启动、重启、替换或重定向该服务。构建时固定的客户端可执行文件，可能与启动共享服务的可执行文件不同；服务端和宿主机也必须可信。
- 必须明确指定准确的设备 serial；仅支持 Android 主用户 0、安全的普通锁屏，以及本次开机后已经正常解锁过的 Android 用户。重启后的首次解锁必须手动完成。不支持密码、图案、生物识别或其他用户。
- 已在 Android 16 上实测一种 Vivo 六槽数字 PIN 界面；新增魅族17／Android13／Flyme10.5.0.0A的精确四位纯数字配置，以受守卫的正常触摸和同源无障碍进度工作。代码中也有严格的 AOSP PIN 解析逻辑；其他变体尚未验证。日常使用不要求屏幕常亮：一次已授权尝试可以唤醒一次，并请求系统认证界面一次。

本分支增加已观察到的 ColorOS 六位 PIN 界面及中文辅助功能计数。2026-10-15，本人录入后保持签名不变的 Find helper 已在新进程中完成一次从黑屏锁定开始的无线解锁：非交互读取钥匙串、六次数字输入成功、返回 `unlocked_confirmed`／exit 0，随后独立确认 keyguard 已解锁。ColorOS 在一次系统认证页请求后，可能还需要点一次经独立校验的 `showPasswordButton`。该验收针对已安装的签名与设备界面，不代表任意重新构建都已获授权。详见 [ColorOS 验证与本人准备](docs/coloros-validation.md)。

2026-10-11，源码基线曾在新的正常进程中，从黑屏锁定起点通过非交互钥匙串读取完成一次解锁，随后另行查询状态确认已解锁。之后一次用户要求的尝试因无法核验窗口，在读取凭据或输入前停止；再后来观察到手机已解锁，但原因未知，不能归因于该尝试。2026-10-12，冻结Flyme源码基线累计四次真实自动解锁均由独立状态核验成功（三次真正黑屏起点，恢复后另一次亮屏锁定起点），正常新进程非交互钥匙串读取成功。但CLI最后触摸后仍exit3／`flyme_progress_missing_ack`，属于已知终态回执误报，不能称CLI成功回执也已修好。主分支保留该实测基线；终态确认修复另存离线验证过、尚未真机验收的可选补丁。使用Flyme前必读[验证总结与本人后续事项](docs/flyme-validation.md)。公开仓库可离线构建检查；重新构建的签名并未配置或真机验收，也不继承本机基线的钥匙串许可。只要无法确认当前身份、焦点、几何结构或时效，安全停止就是预期行为。

## 构建与安装

**Vivo最新验收（2026-10-13）：**恢复原来已授权的Vivo本机版本后，一次真实黑屏锁定→新进程非交互Keychain读取→正常认证的链路返回`unlocked_confirmed/exit0`，耗时36.509秒，另一次独立状态确认secure／user0／unlocked。没有新增本人授权或修改PIN。[最新验证与版本区别](docs/vivo-validation.md)说明：这不代表公开重新构建的签名已真机验收，也不代表魅族CLI误报已修好。本次仅同步文档，不改正在工作的本机App。

在仓库目录执行：

```sh
sh build.sh "$PWD/build"
# SDK not on build-time PATH: sh build.sh "$PWD/build" --adb /absolute/platform-tools/adb
sh check.sh "$PWD/build"
sh install.sh "$PWD/build"
"$HOME/.local/bin/android-unlock" help
```

构建时一次性解析 ADB 软链接，确认目标是可执行的真实普通文件，由当前用户或 root 所有，且不可被组或其他用户写入；然后将绝对路径固定在签名 App bundle 中。运行时不搜索 PATH，也不读取 ADB 路径覆盖参数。若移动客户端，或更新后客户端路径改变，需要重新构建。本项目不宣称提供官方签名或 Apple 公证。

安装位置为 `~/Applications/AndroidUnlockHelper.app` 和 `~/.local/bin/android-unlock`。启动器执行 bundle 内的真实可执行文件，而不是对二进制创建软链接。若目标路径下已存在 App 或启动器，默认拒绝覆盖安装。确实需要更新时，可执行 `sh install.sh "$PWD/build" --replace`；替换前会把原文件保存在本地备份目录。ad-hoc 签名更新可能改变钥匙串信任；安装器不会迁移或授予访问权限。

如需安全地做安装冒烟检查：

```sh
sh install.sh "$PWD/build" --stage "$PWD/build/stage"
"$PWD/build/stage/.local/bin/android-unlock" help
```

隔离安装会复制并验证真实签名 bundle，但**不会让该路径获得首次配置、已有凭据授权或执行已授权解锁的资格**。请使用新的隔离目录；已有目标默认拒绝覆盖。如需测试隔离目录内的替换，可明确指定 `--replace --stage /absolute/stage`。安装器不会执行 ADB、首次配置、授权或任何设备动作。

## 本人一次性准备

只读界面采集器是一份代码资源，不是 APK。由本人明确将仓库附带、固定哈希的 JAR 部署到已授权的设备；助手不会自动上传它：

```sh
adb -s SERIAL push fast-reader/collector.jar /data/local/tmp/page.juns.android-unlock-128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def.jar
adb -s SERIAL shell toybox sha256sum /data/local/tmp/page.juns.android-unlock-128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def.jar
```

本机和设备上的摘要都必须等于 `128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def`。资源缺失或不匹配时，助手会拒绝继续。仓库包含源码和仅供编译的 API 声明。若要重新构建，请自行提供 JDK 和官方 Google R8/D8 JAR，并执行 `sh fast-reader/build.sh /absolute/output /absolute/r8.jar`。重新构建可能改变归档字节；替换受完整性保护的资源，需要有意识地审查并更新固定哈希，不能关闭验证。DEX只包含本项目原创`FastHierarchy`、`FlymeProgressSession`及其生成的监听器类；编译声明不会作为运行时实现发布。详见[来源与许可说明](THIRD_PARTY_NOTICES.zh-CN.md)。

先手动将手机正常解锁、亮屏并保持安全锁屏设置，再由**本机用户本人**执行：

```sh
"$HOME/.local/bin/android-unlock" setup --local-user --serial SERIAL
```

PIN 只在原生掩码输入框中输入。它保存在助手自己的本地通用钥匙串条目中，绑定 macOS UID、设备 serial 和 Android 用户 0。更新后，本人可以运行 `authorize-existing --local-user --serial SERIAL`，在 macOS 管理的钥匙串弹窗中自行决定授权。此操作读取已有条目，不重写 PIN 或 ACL。交互读取成功后，同进程的一次非交互读取，只证明**同进程**可访问；不保证持久权限或下一个进程可访问。Agent 不应代执行这些首次配置或授权流程，也不应在聊天中索要 PIN。

## 日常使用

```sh
android-unlock devices
android-unlock status --serial SERIAL
android-unlock preflight --serial SERIAL
android-unlock unlock --dry-run --serial SERIAL
# Only with authorization for this exact phone:
android-unlock unlock --authorize --serial SERIAL
```

只读命令不会唤醒、呈现认证界面、输入或查询凭据。已授权解锁包含一次有界准备和至多一次 PIN 尝试，不清空、不补输、不重试、不自动重锁。助手要求新鲜、完整的 SystemUI 包/进程/窗口/显示/用户/安全状态证据、已核验的空输入字段、每一位的明确进度，以及两秒的 UI 完成后证据时限。Vivo 已填前缀槽的前景节点，只有在明确位数支持时才允许消失；未填槽、全部背景和完整键盘仍必须存在。一次非秘密占位活动，只能在紧邻的完整证据仍新鲜时复用该证据。Vivo 自动提交后，不会向新解锁的 App 发送 Enter。

回执仅包含固定的非秘密元数据。`unlocked_confirmed` 要求独立读回确认同一设备/用户的 keyguard 状态；`already_unlocked` 表示原本已解锁，不消耗 PIN。命令返回码为 0 并不等同于认证成功，也不代表后续 GUI 或业务操作已经完成。遇到阻止、状态变化、拒绝、超时或部分输入，立即停止；应获取新证据，而不是重放原尝试。退出码：0 表示已观察/已就绪/已确认，2 表示被阻止，3 表示已尝试但未确认，64 表示参数错误。

界面层级字节仅通过匿名 stdout 管道和原生进程内存流转，不写 UI dump 文件或日志。采集器避免使用会记录私密 UI 的系统框架导出器。完整 PIN 不进入命令参数、环境变量、文件、回执或 Agent 上下文；与秘密相关的输入使用私有、非 PTY 的 stdin，并抑制输出。焦点核验与事件派发不是原子操作；有权限的 OS/ADB 观察者仍可能看到输入，也不保证彻底擦除所有 OS/框架内存副本。请使用可信的 Mac、ADB 服务和 Android 系统。

先安装并由本人在本机掩码窗口保存 PIN；Agent 只指定准确 serial、只读检查，并在授权后尝试一次。失败或部分输入立即停止。这里验证的是普通锁屏认证，不代表后续 App 操作已获授权。

## 许可证

原创助手、采集器和安装包装采用 MIT。项目自行编写、仅供编译的 Android API 声明单独采用 Apache-2.0；详见[来源与许可说明](THIRD_PARTY_NOTICES.zh-CN.md)。许可证法律文本以原文为准；本说明仅供参考，不替代许可证正式条款。
