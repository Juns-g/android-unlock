# Vivo 最新验收 / Latest Vivo validation

2026-10-13 · 维护者本机受控测试的脱敏总结，不含原始设备日志或凭据。

## 中文

**结论：Vivo V2324A／Android16的普通黑屏自动解锁，本轮完整通过。** 这仅证明明确设备、当前环境和原已授权冻结版本能正常工作，不是全机型兼容、永久权限或全部项目分支通过。

### 真实执行结果

- 原精确设备重新连接后，独立状态已经是online／secure／user0／黑屏locked。因此虽然用户已明确授权助手用ADB锁屏再测试，本轮没有额外发送SLEEP或POWER。
- 当时安装的Flyme兼容1bb1版正常唤醒并核验PIN界面后，在Vivo自有Keychain条目非交互读取阶段返回`copy_matching/-25293`、exit2／`credential_blocked`／`submitted=false`；0位输入。该失败不证明安卓PIN错误，也不单独确证具体ACL原因，未重读来试运气。
- 维护者核验原已实测Vivo193c完整App备份、签名、启动器和资源，先完整保存1bb1版本，再恢复原稳定安装路径。没有重编译／重签、重录PIN、迁移秘密或修改Keychain ACL。
- 恢复后的唯一正常新进程从真实黑屏locked起点，完成唤醒、正常认证页呈现、完整输入守卫及已有Keychain非交互`read_success/OSStatus0`，普通PIN输入后CLI返回 **`code=0/result=unlocked_confirmed/submitted=true`**，耗时36.509秒。
- 另一个只读status进程再次返回`code=0/result=observed`，确认同设备`online=true/secure=true/androidUser=0/lockState=unlocked`；未读取秘密或发送输入。

原Vivo冻结本机可执行SHA256：`193cf8ddf8673bfc8209cb47eddbee1862931b76b1e0e742164fbdffc335f07e`；资源SHA256：`5582c29de27b979f4a583b3fc16c483d3103d04035b7e294c5e22904fa24a276`。整App及启动器按备份完整比对、严格验签和实际入口help均通过，运行后字节保持不变。哈希仅用于准确区分实测身份，不承诺重新构建能得到相同签名或继承授权。

### 本机可用版本与公开源码区别

当前维护者本机运行原已授权Vivo193c；魅族可用1bb1完整版本另行私有保存，魅族已断开，终态修复仍暂停。公开`main`保留先前同步的Flyme兼容源码基线，不因本机按设备恢复版本而回退远端功能。原公开Vivo源码快照可追溯至[2f3298c](https://github.com/Juns-g/android-unlock/tree/2f3298cfac6ce44865960e833f86b84b9bccd7bf)；公开重新构建不是本机已批准的原App，没有自动继承其权限或真机验证。

不同设备的自有条目绑定serial／user0，同一App版本对一台设备有成功读取证据，不代表其他设备条目也已批准。切换设备先核对精确目标和对应冻结版本，不为“版本统一”重新签名或把秘密迁移到所有App信任。

### 目前还没完成什么

- [Flyme已知末位误报与可选修复](flyme-validation.md)保持原状态：实际手机四次解锁成功，但基线CLI仍末位missing_ack／exit3；候选只有离线检查和限域复核，未完成真机认证。不得把本次Vivo的exit0结果写成魅族也全部通过。
- AOSP解析存在不等于其他机型已实测；密码／图案／生物识别／其他Android用户／手机重启后首次解锁不在自动解锁支持范围。无常驻或无限重试任务。
- 本轮没有新增实现，也未验证公开新构建的凭据访问。本次同步仅为文档和验收事实，不触动正在工作的本机App。

**当前用户无需新增操作。** 今后明确请求解锁Vivo时，可复用现有冻结链路，由助手检查目标、正常尝试一次并独立确认。连接缺失、焦点／用户／身份变化、凭据拒绝、部分输入或未知状态仍停止；不凭ADB退出0断言解锁、不自动重放。只有以后明确选择新签名版本且系统实际拒绝时，才需要本人通过系统UI批准已有条目，不重录或发送聊天PIN。

## English

**The Vivo V2324A / Android 16 ordinary black-screen unlock passed the complete local flow on 2026-10-13.** The reconnected target was already securely locked with its screen off, so no redundant relock event was sent despite explicit authorization for that test.

The locally installed Flyme-capable1bb1 identity initially stopped at the Vivo item's noninteractive Keychain `copy_matching/-25293`, exit2/credential_blocked/submitted=false, with zero digits. This was not evidence of a wrong Android PIN or a specific ACL mechanism; there was no repeated denied read. After verifying and preserving full rollback bundles, the maintainer restored the exact previously approved Vivo193c bundle and launcher, without rebuilding, reenrolling, migrating secrets or changing ACLs.

One new ordinary process then woke/presented/validated the black locked target, obtained the existing own item through noninteractive `read_success/OSStatus0`, and returned **exit0 / unlocked_confirmed / submitted=true** after normal PIN authentication in36.509seconds. A separate read-only process confirmed observed/online/secure/user0/unlocked. Full-bundle byte equality, strict signing and launcher-help checks passed; the running bundle remained unchanged.

The local tested executable SHA256 is `193cf8ddf8673bfc8209cb47eddbee1862931b76b1e0e742164fbdffc335f07e`, with the original `5582c29de27b979f4a583b3fc16c483d3103d04035b7e294c5e22904fa24a276` resource. Hashes distinguish the locally tested identity; they are not promises of reproducible signatures or inherited Keychain grants. Public main retains the previously published Flyme-capable source baseline; restoring a local per-device approved identity is not a reason to revert public functionality. The older public Vivo source is [2f3298c](https://github.com/Juns-g/android-unlock/tree/2f3298cfac6ce44865960e833f86b84b9bccd7bf). Newly rebuilt public code has not inherited the tested App's permissions or live acceptance.

The [Flyme terminal-receipt false negative and optional candidate](flyme-validation.md) remain unresolved as previously documented. This Vivo success does not validate Flyme's candidate, other devices, perpetual access, first authentication after reboot or subsequent application operations. Existing item access is bound per serial/user0; success for another device is not this item's authorization.

There is no new implementation or current owner action in this update. Keep the working frozen App, inspect the exact target before one authorized attempt, and independently confirm the result. Missing connections, refused access, partial input, identity/user changes and unknown states still stop without retry. Only an explicitly chosen new signature and an actual OS access refusal require later owner approval through system UI. No credentials, device serials, private paths, raw traces or OEM samples are published.
