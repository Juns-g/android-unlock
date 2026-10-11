# Flyme 验证总结 / Flyme validation notes

2026-10-12 · 公开、脱敏的维护者测试总结，不是原始设备回执或通用兼容性保证。

## 中文

### 当前发布的是什么

主分支同步的是已实测的精确魅族17／Android13／Flyme10.5.0.0A四位纯数字路径。它保留原有Vivo／AOSP分支，使用正常触摸，不使用数字硬件KeyEvent兜底，不移除锁屏、不root、不安装APK、不改变PIN。

Flyme字段不能按标准AOSP数字密码类型或遮罩长度推断。这里采用动态SystemUI身份、窗口／显示／用户／几何和真实空字段校验；随后在单一有界UiAutomation会话内，以同source-node／window绑定的公开TEXT_CHANGED数值fromIndex／added／removed确认逐位进度，不读取事件text／beforeText。输入前和前三位实际count0／1／2／3、每位完整postUI和原两秒时效仍必须通过；动作派发成功不等于数字已被接受。

已批准的本机冻结App保持原字节，发布代码不替换它、不迁移PIN或ACL，也不创建常驻任务。公开重新构建会得到新的ad-hoc身份，不能继承本机已批准版本的钥匙串访问许可。

### 已核验事实与限制

- 本机冻结实测基线累计四次真实自动解锁成功：前三次从黑屏锁定开始，恢复原App后另一次从亮屏锁定／可信空0开始。每次均正常新进程非交互Keychain读取成功，四次受守卫触摸后，另一次只读status确认同设备／user0／online／secure／unlocked。
- 四次原CLI均exit3，JSON顶层`result=partial_input_aborted_no_retry`，阶段字段`inputObservation.reason=flyme_progress_missing_ack`。后者是本轮精确末位确认误报原因，前者只是泛化结果类别，并非其他失败也可判成功。这是“实际解锁成功、CLI末位确认失败”的已知误报；不能称完整CLI成功，也不能推称收到了第四追加事件。
- 到达第四派发前，前三位真实source-bound进度和完整安全门均已通过。第四事件缺失的具体机制尚未还原；认证结束撤去安全字段是解释，不是已证根因。
- 实测冻结基线曾通过独立构建、384项合成检查、签名与整App一致性复核，以及有界管道验证。合成检查不证明PIN正确、权限永久有效、其他机型兼容或后续App业务可用。
- 新终态候选通过独立393项检查及只读限域复核，但唯一正常黑屏尝试在非交互Keychain读取`copy_matching/-25293`时停止：0数字、独立仍锁定。它没有完成真机认证，也不能被宣称已经修好完整链路。

这些事实来自维护者本机私有受控回执与代码复核。原始回执、设备serial、个人目录、钥匙串内容、厂商APK／overlay／framework样本、反编译实现和聊天记录不发布；公开摘要不是可独立重放的设备日志。

### 如何使用当前基线而不盲重试

保留原始JSON和退出码。只对精确`flyme_four`，原回执同时符合`actionsAttempted=4`、`adbSucceeded=4`和`reason=flyme_progress_missing_ack`的已知末位情形，另取一次新鲜只读状态：

```sh
android-unlock status --serial SERIAL
```

若独立状态确为`observed`、同目标、`online=true`、`androidUser=0`、`secure=true`、`lockState=unlocked`，分别报告“手机实际已解锁”和“CLI仍误报exit3”。不要将原回执改写成`unlocked_confirmed`或伪造count4，不再输入PIN或发送Enter。其他前位失败、派发不足、拒绝、锁定、未知或身份／用户变化仍立即停止；本规则不是覆盖任意exit3的成功包装器。

### 可选终态修复：保留，暂不安装

[flyme-terminal-confirmation.patch](flyme-terminal-confirmation.patch)保存与实测基线相比的最小原创源码差异，仅涉及`NativeProgress.swift`、`Policy.swift`、`Checks.swift`。它未应用到主分支。维护者可先用`git apply --check docs/flyme-terminal-confirmation.patch`核对适用性；是否安装是后续独立步骤。

候选仅在自然通过前位全部守卫、完成四次派发后，使用原独立`confirmUnlock`确认同设备／user0／boot／online上下文且observed／secure／真unlocked，再保留外层追加确认。它不制造第四计数或ACK，不放宽前三位、不改变秘密来源、不增加输入或重试；仍locked／unknown／错设备／错用户／insecure／派发不足时拒绝。

为修回执而换签名造成的授权负担，已经通过恢复原批准版本停止。没有自动重试、自动继续安装或授权任务。

### 必须本人做的事：以后再做，当前没有新增操作

当前本机已批准版本可以继续使用，不要求重新保存PIN或再次授权。只有以后**明确决定换到新签名候选**，且系统实际拒绝访问已有条目时，才由本机用户：

1. 手动正常解锁手机并保持亮屏。
2. 在Mac亲自运行`android-unlock authorize-existing --local-user --serial SERIAL`，自行批准macOS的已有条目访问提示。不重录PIN、不把PIN发给Agent、不扩大到所有App或解释器信任。

正常回执仅证明同进程授权结果。之后由助手保持该版本字节冻结，完成新的正常非交互进程解锁和独立状态验收；这些技术工作不交给用户。手机本次开机的首次正常解锁以及首次ADB信任提示，本来也只能由本人完成，不应为已经在线、已信任的连接反复要求批准。

Flyme隐私前提另须保留：测试中本人设备的`secure.speak_password`原为1，维护者在明确范围内改为0并读回，以避免厂商事件加入此前真实文本；旧值已私有保存用于恢复。公开程序不会替用户改这个设置。新使用者应在采集／输入之前核对并关闭密码朗读，不读取或记录event text／beforeText；不得将这一配置解读为已防御所有特权OS／ADB观察。厂商隐私模式不明或开启、UI结构未知时，不得套用本机合同盲输。

## English

### Published baseline and evidence

Main contains the tested narrow four-digit numeric Meizu 17 / Android 13 / Flyme 10.5.0.0A path, retaining Vivo/AOSP branches. It uses guarded ordinary touches, no numeric hardware-KeyEvent fallback, and source/window-bound numeric accessibility progress in a single bounded UiAutomation session. It does not read event text/before-text, bypass credentials, root the phone, install an APK or change the PIN.

The frozen locally approved baseline physically unlocked four times: three black/locked starts and one awake/locked, verified-empty start after restoration. Each used a fresh normal process and successful noninteractive Keychain access, then independent same-target/user0/online/secure/unlocked status. All four CLI receipts nevertheless exited 3 with `flyme_progress_missing_ack`: physical success is not a successful CLI receipt, and the fourth append event was not proven. The earlier count0/1/2/3, identity and original two-second freshness gates remain mandatory.

The baseline passed independent build/check (384 synthetic checks), signing and complete-bundle comparisons. The optional terminal-only candidate passed 393 synthetic checks and a limited read-only review, but its one normal black-start attempt stopped at Keychain `copy_matching/-25293`, with zero digits and an independently locked target. It has not passed live authentication. Neither test counts nor the local grant imply universal compatibility, permanent access or an enrolled new public build.

This is a maintainer-authored summary of private controlled evidence, not public replayable raw logs. No serials, personal paths, Keychain data, OEM APKs/overlays/framework samples, decompiled implementations or chat transcripts are published.

### Handling the known false negative

Preserve the original exit code and JSON. Only for `flyme_four` with all of `actionsAttempted=4`, `adbSucceeded=4` and `reason=flyme_progress_missing_ack`, obtain one fresh read-only `status --serial SERIAL`. Independently observed same-target online/secure/user0/unlocked proves physical completion, not a corrected CLI result. Do not fabricate count4/ACK4 or rewrite the old receipt, retry, clear, append or send Enter. Earlier failures, insufficient dispatch, refusal, locked/unknown state or identity/user changes remain stopped. This is not a general nonzero-exit-to-success wrapper.

### Optional candidate and deferred owner action

[The optional patch](flyme-terminal-confirmation.patch) changes only `NativeProgress.swift`, `Policy.swift` and `Checks.swift`; it is not applied to main. It replaces the unobservable final-ACK prerequisite with the existing independent terminal keyguard confirmation, only after the guarded loop naturally dispatches all four actions; outer confirmation remains. No earlier progress gate or credential source is changed. Locked, unknown, wrong device/user, insecure or incomplete-dispatch cases fail closed. Offline checks are not live acceptance.

Keep the working approved App unchanged. No new owner action is currently needed for that local baseline. Only if the owner later elects to install a new signed candidate and macOS actually refuses its existing-item access must the owner manually unlock/keep the phone awake, then personally run `authorize-existing --local-user --serial SERIAL` and decide in the macOS-owned dialog. No PIN reenrollment or chat secret is needed. The assistant owns the subsequent frozen-version, fresh-process live acceptance and independent status checks; same-process authorization is not a permanent grant. First unlock after phone reboot and initial ADB trust remain human-only prerequisites, not repeated prompts for an already trusted online connection.

Privacy prerequisite: on the test device, the operator deliberately changed user0 `secure.speak_password` from 1 to 0 and verified it; the original value remains privately recoverable. Public code does not change that setting. New users must verify/disable password speech before collection/input, never inspect or log event text/before-text, and must not infer protection from all privileged OS/ADB observation. Unknown/enabled OEM privacy mode or unknown UI contracts must not be treated as this verified profile.
