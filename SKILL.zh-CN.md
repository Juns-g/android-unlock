# Android 普通锁屏 Skill 使用说明

[English](SKILL.md) | [简体中文](SKILL.zh-CN.md)

Agent 自动发现入口保持为 `SKILL.md`；本文件是中文对照说明，不另行注册第二个 Skill。

在 macOS 上使用已安装的本地 `~/.local/bin/android-unlock` CLI。遇到安装、兼容性、采集器缺失或首次配置问题时，读取相对于本 Skill 仓库目录的 [README 中文版](README.zh-CN.md)。若 CLI 未安装，请立即停止并提示该前置条件缺失；安装与配置属于本机用户的独立操作。

1. 执行 `"$HOME/.local/bin/android-unlock" devices`，从非秘密列表中选择用户指定设备的准确 serial；不得隐式选择写入目标。
2. 通过同一个 CLI 执行 `status --serial SERIAL`，然后执行 `unlock --dry-run --serial SERIAL`。身份、焦点、状态未知或前提缺失时，视为被阻止。只读命令不唤醒设备，也不读取钥匙串。
3. 用户已授权此手机的普通解锁后，**只执行一次**：`"$HOME/.local/bin/android-unlock" unlock --authorize --serial SERIAL`。它包含有界唤醒和认证界面呈现；不要求屏幕常亮。
4. 按固定 JSON 回执报告结果。`unlocked_confirmed` 表示已独立核验；`already_unlocked` 表示无需 PIN、没有输入的已解锁状态。被阻止、拒绝、未确认或部分输入时，立即停止并报告准确的安全类别。不重试、不清空、不补输、不覆盖凭据来源。

只有本机用户本人可以执行 `setup --local-user` 或 `authorize-existing --local-user`，并且秘密只在原生/系统 UI 中输入。不得通过聊天、argv、环境变量、文件或其他工具索要、获取或传递 PIN。请保持既有的可信 ADB 连接、专属钥匙串条目以及所有安全校验规则不变。解锁后的 App/业务动作需要各自的授权；解锁本身不执行这些动作。
