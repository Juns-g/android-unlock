import Foundation
import AppKit
import Security
import Darwin

#if HYPEROS_STANDALONE
let identity = "page.juns.AndroidUnlockHyperOSHelper"
let helperAppName = "AndroidUnlockHyperOSHelper"
#else
let identity = "page.juns.AndroidUnlockHelper"
let helperAppName = "AndroidUnlockHelper"
#endif
let service = "page.juns.android-unlock.pin.v1"
let stablePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/" + helperAppName + ".app/Contents/MacOS/android-unlock").path
let adbPath = Bundle.main.object(forInfoDictionaryKey: "AndroidUnlockADBPath") as? String ?? ""
// Build-pinned real path and private environment: no runtime PATH search or ADB_TRACE.
func trustedADB() -> Bool {
    guard adbPath.hasPrefix("/"), URL(fileURLWithPath: adbPath).resolvingSymlinksInPath().path == adbPath else { return false }
    var st = stat()
    return lstat(adbPath, &st) == 0 && st.st_mode & S_IFMT == S_IFREG && st.st_mode & 0o022 == 0 &&
        (st.st_uid == getuid() || st.st_uid == 0) && access(adbPath, X_OK) == 0
}
struct Output { let data: Data; let ok: Bool; var errorData = Data() }
func runADB(_ args: [String], timeout: Double = 4, confidential: Data? = nil, captureErrors: Bool = false) -> Output {
    guard trustedADB() else { return Output(data: Data(), ok: false) }
    // Do not start/restart the server: require an existing listening local socket first.
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return Output(data: Data(), ok: false) }
    var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(5037).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    close(sock)
    guard connected == 0 else { return Output(data: Data(), ok: false) }
    let process = Process(); let output = Pipe(); let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: adbPath)
    process.arguments = ["-H", "127.0.0.1", "-P", "5037"] + args
    process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LC_ALL": "C"]
    let input = Pipe()
    process.standardInput = confidential == nil ? FileHandle.nullDevice : input.fileHandleForReading
    process.standardOutput = confidential == nil ? output : FileHandle.nullDevice; process.standardError = captureErrors && confidential == nil ? errors : FileHandle.nullDevice
    do { try process.run() } catch { return Output(data: Data(), ok: false) }
    input.fileHandleForReading.closeFile()
    if let confidential { input.fileHandleForWriting.write(confidential) }
    input.fileHandleForWriting.closeFile()
    output.fileHandleForWriting.closeFile()
    errors.fileHandleForWriting.closeFile()
    let handles = [output.fileHandleForReading, errors.fileHandleForReading]
    for handle in handles { _ = fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) }
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    var captured = [Data(), Data()]; var exceeded = false; var timedOut = false
    var eof = [false, false]; var bytes = [UInt8](repeating: 0, count: 8192)
    while !eof.allSatisfy({ $0 }) {
        var received = false
        for i in handles.indices where !eof[i] {
            let n = read(handles[i].fileDescriptor, &bytes, bytes.count)
            if n > 0 {
                received = true
                if captured[0].count + captured[1].count + n <= 1_048_576 { captured[i].append(contentsOf: bytes.prefix(n)) }
                else { exceeded = true }
            } else if n == 0 { eof[i] = true }
            else if errno != EAGAIN && errno != EINTR { exceeded = true }
        }
        if exceeded || ProcessInfo.processInfo.systemUptime >= deadline { timedOut = true; break }
        if !received { Thread.sleep(forTimeInterval: 0.005) }
    }
    while process.isRunning && !timedOut && !exceeded {
        if ProcessInfo.processInfo.systemUptime >= deadline { timedOut = true; break }
        Thread.sleep(forTimeInterval: 0.005)
    }
    if process.isRunning && (timedOut || exceeded) {
        // Terminate this adb client; secret-side remote shell is independently bounded by toybox timeout.
        process.terminate()
        let until = ProcessInfo.processInfo.systemUptime + 0.15
        while process.isRunning && ProcessInfo.processInfo.systemUptime < until { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    process.waitUntilExit(); handles.forEach { $0.closeFile() }
    return Output(data: captured[0], ok: !timedOut && !exceeded && process.terminationStatus == 0, errorData: captured[1])
}
func inventory() -> [Device]? {
    let r = runADB(["devices", "-l"])
    guard r.ok, let t = String(data: r.data, encoding: .utf8) else { return nil }
    return devices(t)
}
func readBatch(_ serial: String, _ commands: [(String, String)]) -> [String: String]? {
    guard let args = batchArguments(serial, commands: commands) else { return nil }
    let output = runADB(args, timeout: 6)
    guard output.ok else { return nil }
    return parseBatch(output.data, names: commands.map { $0.0 })
}
func snapshot(_ serial: String, queryTarget: Bool = true, reusingUI: Snapshot? = nil, progress: FlymeNativeProgress? = nil) -> Snapshot {
    var s = Snapshot(); s.serial = serial
    let d = deviceDecision(inventory(), serial: serial)
    guard d == "online" else { s.reason = d; return s }
    guard let state = readBatch(serial, stateCommands) else { s.reason = "state_query_failed"; return s }
    guard deviceDecision(inventory(), serial: serial) == "online" else { s.reason = "device_changed"; return s }
    s = parseState(serial: serial, userText: state["user"]!, policyText: state["policy"]!)
    guard s.reason == "observed" || s.reason == "screen_state_unknown" else { return s }
    s.userUnlocked = state["started"]!.trimmingCharacters(in: .whitespacesAndNewlines) == "RUNNING_UNLOCKED"
    guard queryTarget && s.state == .locked && s.awake && s.userUnlocked && s.bootComplete && s.secure else { return s }
    guard let fields = readBatch(serial, identityCommands) else { s.focusResult = "focus_query_failed"; return s }
    let focus = focusObservation(windows: fields["windows"]!, displays: fields["displays"]!)
    s.focusResult = focus.result; s.focusSource = focus.source; s.focusDisplayID = focus.displayID
    guard let line = focus.line else { return s }
    let pid = fields["pid"]!.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let process = processCommand(pid) else { s.focusResult = "systemui_pid_unverified"; return s }
    guard let second = readBatch(serial, [process, ("hash", "toybox sha256sum " + collectorDevicePath)]),
          let identity = systemUIIdentity(packageList: fields["packages"]!, packageDump: fields["package"]!, process: second["process"]!, pid: pid) else {
        s.focusResult = "systemui_system_package_process_unverified"; return s
    }
    guard verifiedWindow(fields["windows"]!, target: PinTarget(window: line, field: "", count: 0), pid: identity.pid, uid: identity.uid) else {
        s.focusResult = "focus_owner_session_role_unverified"; return s
    }
    s.focusResult = "focus_identity_verified"
    var reused = false
    if let previous = reusingUI {
        switch uiReuse(previous, s, window: line, now: ProcessInfo.processInfo.systemUptime) {
        case .blocked: s.reason = "ui_evidence_stale_or_changed"; return s
        case .reuse:
            s.target = previous.target; s.coverWindow = previous.coverWindow; s.coverBounds = previous.coverBounds; s.coverIsVivo = previous.coverIsVivo; s.coverIsFlyme = previous.coverIsFlyme
            s.coverIsColorOS = previous.coverIsColorOS; s.colorOSRevealButton = previous.colorOSRevealButton
            s.observedAt = previous.observedAt; reused = true
        case .refresh: break
        }
    }
    if !reused {
        let resource = Bundle.main.url(forResource: "fast-reader", withExtension: "jar")
        let resourceStatus = collectorResourceResult(resource.flatMap { try? Data(contentsOf: $0) })
        guard resourceStatus == "verified" else { s.hierarchyResult = resourceStatus; return s }
        guard collectorDeviceHashMatches(second["hash"]!) else { s.hierarchyResult = "hierarchy_collector_device_code_mismatch"; return s }
        guard let readerArgs = fastReaderArguments(serial) else { s.hierarchyResult = "hierarchy_collector_serial_invalid"; return s }
        let hierarchy: Output
        let progressCount: Int?
        if let progress {
            hierarchy = progress.snapshotOutput(); progressCount = progress.observedCount.flatMap { $0 > 0 ? $0 : nil }
        } else { hierarchy = runADB(readerArgs, timeout: 6, captureErrors: true); progressCount = nil }
        s.hierarchyStdoutEmpty = hierarchy.data.isEmpty; s.hierarchyStderrPresent = !hierarchy.errorData.isEmpty
        let parsed = String(data: hierarchy.data, encoding: .utf8).flatMap { parseHierarchy($0, flymeProgressCount: progressCount) }
        s.hierarchyResult = hierarchyDiagnostic(hierarchy.data, stderr: hierarchy.errorData, ok: hierarchy.ok, parsed: parsed)
        if let progress, !hierarchy.ok { s.hierarchyResult = progress.result }
        guard s.hierarchyResult == "hierarchy_xml_parsed", let parsed else { return s }
        if coverHierarchy(parsed) { s.coverWindow = line; s.coverBounds = vivoCoverBounds(parsed); s.coverIsVivo = coverHierarchy(parsed, requireVivo: true); s.coverIsFlyme = !s.coverIsVivo && parsed.flymeCover }
        s.target = pinTarget(delegate: parsed, windowText: line)
        if s.target == nil, !parsed.bad {
            s.target = colorOSPinTarget(String(decoding: hierarchy.data, as: UTF8.self), window: line)
        }
        if s.target == nil, !parsed.bad, !parsed.pinPresent,
           let area = colorOSCoverBounds(String(decoding: hierarchy.data, as: UTF8.self)) {
            s.coverWindow = line; s.coverBounds = area; s.coverIsColorOS = true
        }
        if s.target == nil, !parsed.bad, !parsed.pinPresent,
           let invitation = colorOSInvitation(String(decoding: hierarchy.data, as: UTF8.self)) {
            s.coverWindow = line; s.coverBounds = invitation.bounds; s.coverIsColorOS = true
            s.colorOSRevealButton = invitation.button
        }
        s.observedAt = ProcessInfo.processInfo.systemUptime
        if s.target == nil && s.coverWindow == nil {
            if parsed.flymeNodes["mz_keyguard_pin_view"] != nil { s.hierarchyResult = "hierarchy_flyme_" + parsed.flymeFailure }
            else if parsed.hyperosNodes["keyguard_pin_view"] != nil { s.hierarchyResult = "hierarchy_hyperos_" + parsed.hyperosFailure }
            else { s.hierarchyResult = "hierarchy_secure_target_unverified" }
        }
    }
    // Recheck state AND full SystemUI identity after UI; cached evidence keeps its original timestamp.
    let postStarted = ProcessInfo.processInfo.systemUptime
    let flyme = s.coverIsFlyme || s.target?.mode == .flymeFour
    let post = readBatch(serial, identityCommands + [process] + stateCommands + (flyme ? [flymeCodeCommand, flymePrivateModeCommand, flymeSpeechCommand] : []))
    let postCompleted = ProcessInfo.processInfo.systemUptime
    s.postUIStateCheckSeconds = postCompleted - postStarted
    guard let post, deviceDecision(inventory(), serial: serial) == "online" else {
        s.reason = "post_ui_query_or_device_failed"; s.target = nil; s.coverWindow = nil; s.coverBounds = nil; return s
    }
    if flyme, !flymeSystemUICodeMatches(post["flymeCode"] ?? "") {
        s.reason = "flyme_systemui_code_unverified"; s.target = nil; s.coverWindow = nil; s.coverBounds = nil; return s
    }
    if flyme, !flymePrivateModeDisabled(post["flymePrivateMode"]) {
        s.reason = "flyme_private_mode_unverified"; s.target = nil; s.coverWindow = nil; s.coverBounds = nil; return s
    }
    if flyme, !flymeSpeechDisabled(post["flymeSpeech"]) {
        s.reason = "flyme_speech_privacy_unverified"; s.target = nil; s.coverWindow = nil; s.coverBounds = nil; return s
    }
    var after = parseState(serial: serial, userText: post["user"]!, policyText: post["policy"]!)
    after.userUnlocked = post["started"]!.trimmingCharacters(in: .whitespacesAndNewlines) == "RUNNING_UNLOCKED"
    let postFocus = focusObservation(windows: post["windows"]!, displays: post["displays"]!)
    let postIdentity = systemUIIdentity(packageList: post["packages"]!, packageDump: post["package"]!, process: post["process"]!, pid: pid)
    let sameIdentity = postFocus.line == line && post["pid"]!.trimmingCharacters(in: .whitespacesAndNewlines) == pid &&
        postIdentity?.uid == identity.uid && postIdentity?.pid == identity.pid &&
        verifiedWindow(post["windows"]!, target: PinTarget(window: line, field: "", count: 0), pid: identity.pid, uid: identity.uid)
    let compatible = postUICompatible(s, after, sameIdentity: sameIdentity, uiObservedAt: s.observedAt, now: ProcessInfo.processInfo.systemUptime)
    s.state = after.state; s.awake = after.awake; s.screenKnown = after.screenKnown; s.user = after.user
    s.secure = after.secure; s.bootComplete = after.bootComplete; s.userUnlocked = after.userUnlocked
    s.postUIStateChecked = true
    s.postUIVerifiedAt = compatible ? ProcessInfo.processInfo.systemUptime : 0
    if !compatible { s.reason = "state_or_identity_changed_during_ui"; s.target = nil; s.coverWindow = nil; s.coverBounds = nil }
    return s
}
func setup(_ initial: Snapshot) -> String {
    guard getuid() != 0, getuid() == geteuid(),
          Bundle.main.executableURL?.resolvingSymlinksInPath().path == stablePath,
          Bundle.main.bundleIdentifier == identity else { return "install_at_stable_path_first" }
    guard initial.reason == "observed", initial.state == .unlocked, initial.awake, initial.secure, initial.user == 0, initial.userUnlocked, initial.bootComplete else {
        return "setup_requires_unlocked_secure_primary_user"
    }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
          let code, SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return "signature_invalid" }
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let alert = NSAlert(); alert.messageText = "AndroidUnlockHelper：在本机设置数字 PIN"
    alert.informativeText = "仅绑定设备 \(initial.serial)、Android 用户 0。只支持已验证安全字段的一次普通锁屏输入。不要通过聊天、命令或剪贴板提供 PIN。"
    alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    alert.accessoryView = field; alert.window.initialFirstResponder = field; app.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return "setup_cancelled" }
    var pin = Data(field.stringValue.utf8); field.stringValue = ""
    defer { pin.resetBytes(in: 0..<pin.count) }
    guard validPIN(pin) else { return "numeric_pin_4_to_16_only" }
    let after = snapshot(initial.serial)
    guard consistent(initial, after), after.reason == "observed", after.state == .unlocked, after.secure else { return "device_or_user_changed" }
    var trusted: SecTrustedApplication?
    guard SecTrustedApplicationCreateFromPath(stablePath, &trusted) == errSecSuccess, let trusted else { return "trusted_access_failed" }
    var access: SecAccess?
    guard SecAccessCreate("AndroidUnlockHelper own PIN" as CFString, [trusted] as CFArray, &access) == errSecSuccess, let access else { return "trusted_access_failed" }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: "uid:\(getuid());serial:\(initial.serial);android-user:0", kSecAttrSynchronizable as String: false,
        kSecUseDataProtectionKeychain as String: false]
    let values: [String: Any] = [kSecValueData as String: pin, kSecAttrAccess as String: access]
    let result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if result == errSecSuccess { return "pin_saved" }
    guard result == errSecItemNotFound else { return "keychain_save_blocked" }
    var add = query; values.forEach { add[$0.key] = $0.value }; add[kSecAttrLabel as String] = "AndroidUnlockHelper (own item)"
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? "pin_saved" : "keychain_save_blocked"
}

func ownQuery(_ serial: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: "uid:\(getuid());serial:\(serial);android-user:0", kSecAttrSynchronizable as String: false,
     kSecUseDataProtectionKeychain as String: false]
}
func authorizeExisting(_ initial: Snapshot) -> ExistingAuthorization {
    guard getuid() != 0, getuid() == geteuid(),
          Bundle.main.executableURL?.resolvingSymlinksInPath().path == stablePath,
          Bundle.main.bundleIdentifier == identity else { return ExistingAuthorization(result: "install_at_stable_path_first") }
    guard existingAuthorizationEligible(initial) else { return ExistingAuthorization(result: "authorization_requires_unlocked_secure_primary_user") }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
          let code, SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return ExistingAuthorization(result: "signature_invalid") }
    return verifyExistingAuthorization(interactiveRead: { retrievePIN(initial.serial, interactive: true) },
        noninteractiveRead: { fetchPIN(initial.serial) })
}
func retrievePIN(_ serial: String, interactive: Bool) -> CredentialRead {
    readCredential(interactive: interactive, setInteraction: { SecKeychainSetUserInteractionAllowed($0) }, query: {
        var q = ownQuery(serial); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = interactive ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        return (status, item)
    })
}
func fetchPIN(_ serial: String) -> CredentialRead { retrievePIN(serial, interactive: false) }
func submitPIN(_ pin: Data, initial: Snapshot, report: ((Snapshot, Int, Int) -> Void)? = nil) -> InputResult {
    if initial.target?.mode == .flymeFour { return submitFlymeProgressPIN(pin, initial: initial, report: report) }
    let deadline = ProcessInfo.processInfo.systemUptime + 90
    var last = initial; var first = true; var actions = 0; var adbSucceeded = 0
    return drivePIN(pin, initial: initial, observe: { finalOEM in
        var now = finalOEM ? confirmUnlock(initial) : snapshot(initial.serial, reusingUI: first ? initial : nil)
        if !finalOEM && !first && now.target != nil { now = snapshot(initial.serial, reusingUI: now) }
        first = false; last = now
        if ProcessInfo.processInfo.systemUptime >= deadline { now.reason = "input_deadline" }
        report?(now, actions, adbSucceeded)
        return now
    }, send: { key in
        let command: String
        if last.target?.mode == .vivoSix || last.target?.mode == .flymeFour || last.target?.mode == .colorOSSix || last.target?.mode == .hyperos {
            guard (7...16).contains(key), let rect = last.target?.keys[key - 7] else { return false }
            let point = rect.center; command = "tap \(point.0) \(point.1)"
        } else { command = "keyevent \(key)" }
        var payload = Data("exec /system/bin/input \(command)\n".utf8)
        defer { payload.resetBytes(in: 0..<payload.count) }
        // One digit-dependent action per private stdin payload; suppressed output, no secret argv.
        actions += 1
        let r = runADB(["-s", initial.serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/sh"], timeout: 4, confidential: payload)
        if r.ok { adbSucceeded += 1 }
        report?(last, actions, adbSucceeded)
        return r.ok
    })
}
func confirmUnlock(_ initial: Snapshot) -> Snapshot {
    let deadline = ProcessInfo.processInfo.systemUptime + 8
    var s = initial
    repeat {
        s = snapshot(initial.serial, queryTarget: false)
        if !consistent(initial, s) || s.reason != "observed" || s.state == .unlocked { return s }
        Thread.sleep(forTimeInterval: 0.2)
    } while ProcessInfo.processInfo.systemUptime < deadline
    return s
}
func acquireLock() -> Int32? {
    let directory = NSTemporaryDirectory() + "android-unlock-\(getuid())"
    if mkdir(directory, 0o700) != 0 && errno != EEXIST { return nil }
    let dir = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard dir >= 0 else { return nil }; defer { close(dir) }
    var st = stat()
    guard fstat(dir, &st) == 0, st.st_uid == getuid(), st.st_mode & 0o777 == 0o700 else { return nil }
    let fd = openat(dir, "attempt.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return nil }
    guard fstat(fd, &st) == 0, st.st_uid == getuid(), st.st_nlink == 1, st.st_mode & S_IFMT == S_IFREG,
          st.st_mode & 0o777 == 0o600, flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
    return fd
}

func preparationKey(_ serial: String, key: Int) -> Bool {
    guard key == 224 || key == 62 else { return false }
    // Fixed nonsecret event; timeout bounds the remote command. Never KEYCODE_POWER.
    return runADB(["-s", serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/input", "keyevent", String(key)], timeout: 4).ok
}
func prepareNative(_ initial: Snapshot) -> Preparation {
    var latest = initial
    return prepare(initial, authorized: true, observe: {
        if immediateCoverObservation(initial, latest, now: ProcessInfo.processInfo.systemUptime) { return latest }
        latest = snapshot(initial.serial, reusingUI: latest.coverWindow != nil ? latest : nil); return latest
    },
            wake: { preparationKey(initial.serial, key: 224) }, afterWake: {
                let deadline = ProcessInfo.processInfo.systemUptime + 6
                var current = snapshot(initial.serial)
                while canSettleWake(initial, current), !current.awake,
                      ProcessInfo.processInfo.systemUptime < deadline {
                    Thread.sleep(forTimeInterval: 0.15)
                    current = snapshot(initial.serial)
                }
                latest = current; return latest
            },
            present: {
                guard immediateCoverObservation(initial, latest, now: ProcessInfo.processInfo.systemUptime) else { return false }
                if latest.coverIsColorOS {
                    return prepareColorOSPage(initial: initial, current: &latest,
                        now: { ProcessInfo.processInfo.systemUptime }, observe: { snapshot(initial.serial) },
                        request: {
                            guard let args = wmAuthenticationArguments(initial.serial) else { return false }
                            let output = runADB(args, timeout: 4, captureErrors: true)
                            return wmAuthenticationCommandOK(stdout: output.data, stderr: output.errorData, ok: output.ok)
                        }, tap: { rect in
                            let point = rect.center
                            return runADB(["-s", initial.serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/input", "tap", String(point.0), String(point.1)], timeout: 4).ok
                        })
                }
                if latest.coverIsVivo || latest.coverIsFlyme {
                    guard (!latest.coverIsVivo || latest.coverBounds != nil), let args = wmAuthenticationArguments(initial.serial) else { return false }
                    let output = runADB(args, timeout: 4, captureErrors: true)
                    return wmAuthenticationCommandOK(stdout: output.data, stderr: output.errorData, ok: output.ok)
                }
                if let area = latest.coverBounds {
                    let x = area.center.0; let from = area.y1 + (area.y2 - area.y1) * 3 / 4; let to = area.y1 + (area.y2 - area.y1) / 4
                    return runADB(["-s", initial.serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/input", "swipe", String(x), String(from), String(x), String(to), "250"], timeout: 4).ok
                }
                return preparationKey(initial.serial, key: 62)
            }, afterPresent: { snapshot(initial.serial) })
}

func pinActivity(_ initial: Snapshot, authorized: Bool) -> Bool {
    guard activityEligible(initial, authorized: authorized), let rect = initial.target?.placeholder else { return false }
    let point = rect.center
    guard immediateTrustedVivoPinObservation(initial, serial: initial.serial, authorized: authorized,
                                           now: ProcessInfo.processInfo.systemUptime) else { return false }
    return runADB(["-s", initial.serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/input", "tap", String(point.0), String(point.1)], timeout: 4).ok
}
