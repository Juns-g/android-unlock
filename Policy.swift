import Foundation
import CryptoKit

let collectorSHA256 = "128aa630e499e74824068851815b1a547899060ab1a9d77dbaff3fd497d79def"
let collectorDevicePath = "/data/local/tmp/page.juns.android-unlock-" + collectorSHA256 + ".jar"
let flymeSystemUIPath = "/system_ext/priv-app/SystemUI/SystemUI.apk"
let flymeSystemUISHA256 = "3f31b7cee25e0c70bf56bda87350ef5011cca24858ac2d80e3751f363c7c9b30"
let flymeCodeCommand = ("flymeCode", "toybox sha256sum " + flymeSystemUIPath)
let flymeSpeechCommand = ("flymeSpeech", "settings --user 0 get secure speak_password")
func flymeSpeechDisabled(_ value: String?) -> Bool {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
    return value == "0" || value == "null"
}
let flymePrivateModeCommand = ("flymePrivateMode", "settings get global mz_private_mode")
func flymePrivateModeDisabled(_ text: String?) -> Bool {
    guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
    return value == "0" || value == "null" // The audited constructor/observer defaults an unset key to zero.
}
func flymeSystemUICodeMatches(_ text: String) -> Bool {
    text.split(whereSeparator: { $0.isWhitespace }).map(String.init) == [flymeSystemUISHA256, flymeSystemUIPath]
}
func collectorResourceResult(_ data: Data?) -> String {
    guard let data else { return "hierarchy_collector_resource_missing" }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return digest == collectorSHA256 ? "verified" : "hierarchy_collector_resource_mismatch"
}
func collectorDeviceHashMatches(_ text: String) -> Bool {
    let rows = text.split(separator: "\n").filter { !$0.isEmpty }
    guard rows.count == 1 else { return false }
    let parts = rows[0].split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return parts == [collectorSHA256, collectorDevicePath]
}
func fastReaderArguments(_ serial: String) -> [String]? {
    guard validSerial(serial) else { return nil }
    let pipeline = "'/system/bin/uiautomator runtest " + collectorDevicePath + " -c page.juns.androidunlock.FastHierarchy#testDump -s | /system/bin/cat'"
    return ["-s", serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "4", "/system/bin/sh", "-c", pipeline]
}
let stateCommands = [("user", "am get-current-user"), ("policy", "dumpsys window policy"), ("started", "am get-started-user-state 0")]
let identityCommands = [("windows", "dumpsys window windows"), ("displays", "dumpsys window displays"),
    ("pid", "pidof com.android.systemui"), ("packages", "pm list packages -U --user 0 com.android.systemui"), ("package", "dumpsys package com.android.systemui")]
func processCommand(_ pid: String) -> (String, String)? {
    guard !pid.isEmpty, pid.count <= 10, pid.utf8.allSatisfy({ (48...57).contains($0) }), Int(pid).map({ $0 > 0 }) == true else { return nil }
    return ("process", "ps -p " + pid + " -o UID,PID,NAME")
}
func batchArguments(_ serial: String, commands: [(String, String)]) -> [String]? {
    guard validSerial(serial), !commands.isEmpty, commands.count <= 12 else { return nil }
    let allowed = stateCommands + identityCommands + [("hash", "toybox sha256sum " + collectorDevicePath), flymeCodeCommand, flymePrivateModeCommand, flymeSpeechCommand]
    guard Set(commands.map { $0.0 }).count == commands.count, commands.allSatisfy({ part in
        allowed.contains { $0 == part } || (part.0 == "process" && part.1.hasPrefix("ps -p ") && processCommand(String(part.1.dropFirst(6).prefix(while: { $0 != " " })))?.1 == part.1)
    }) else { return nil }
    let script = commands.map { name, command in
        "printf \"%s\\n\" \"__AU_BEGIN_" + name + "__\"; " + command + "; au_status=$?; printf \"\\n%s:%s\\n\" \"__AU_END_" + name + "__\" \"$au_status\"; if [ \"$au_status\" -ne 0 ]; then exit \"$au_status\"; fi"
    }.joined(separator: "; ")
    return ["-s", serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "4", "/system/bin/sh", "-c", "'" + script + "'"]
}
func parseBatch(_ data: Data, names: [String]) -> [String: String]? {
    guard data.count <= 1_048_576, Set(names).count == names.count, let text = String(data: data, encoding: .utf8) else { return nil }
    let lines = text.components(separatedBy: "\n"); var index = 0; var result: [String: String] = [:]
    for name in names {
        guard index < lines.count, lines[index] == "__AU_BEGIN_" + name + "__" else { return nil }; index += 1
        var body: [String] = []; var bytes = 0
        while index < lines.count, !lines[index].hasPrefix("__AU_") {
            bytes += lines[index].utf8.count + 1; guard bytes <= 524_288 else { return nil }
            body.append(lines[index]); index += 1
        }
        guard index < lines.count, lines[index] == "__AU_END_" + name + "__:0" else { return nil }; index += 1
        result[name] = body.joined(separator: "\n")
    }
    guard lines.dropFirst(index).allSatisfy({ $0.isEmpty }) else { return nil }
    return result
}
func postUICompatible(_ before: Snapshot, _ after: Snapshot, sameIdentity: Bool, uiObservedAt: Double, now: Double) -> Bool {
    consistent(before, after) && after.reason == "observed" && before.state == .locked && after.state == .locked &&
        before.awake && after.awake && before.secure && after.secure && sameIdentity && uiObservedAt > 0 && now >= uiObservedAt && now - uiObservedAt <= 2
}
enum LockState: String, Codable { case locked, unlocked, unknown }
struct Device: Equatable { let serial: String; let state: String }
func validSerial(_ s: String) -> Bool {
    !s.isEmpty && s.utf8.count <= 128 && !s.hasPrefix(" ") && !s.hasSuffix(" ") && !s.contains("  ") && s.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [32, 40, 41, 45, 46, 58, 95].contains($0)
    }
}
func devices(_ text: String) -> [Device]? {
    let lines = text.split(separator: "\n").map(String.init)
    guard lines.first == "List of devices attached" else { return nil }
    var result: [Device] = []
    let states = ["device", "offline", "unauthorized", "no"]
    for line in lines.dropFirst() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        let p = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        // adb inserts " (N)" into duplicate mDNS serials, so the state is the first known token, not field 2.
        guard let stateIndex = p.firstIndex(where: { states.contains($0) }), stateIndex > 0 else { return nil }
        let serial = p[..<stateIndex].joined(separator: " ")
        guard validSerial(serial), !result.contains(where: { $0.serial == serial }) else { return nil }
        result.append(Device(serial: serial, state: p[stateIndex]))
    }
    return result
}
func deviceDecision(_ list: [Device]?, serial: String) -> String {
    guard validSerial(serial) else { return "invalid_serial" }
    guard let list else { return "adb_inventory_unverified" }
    guard let match = list.first(where: { $0.serial == serial }) else { return "device_missing" }
    return match.state == "device" ? "online" : "device_not_authorized_online"
}
struct Snapshot: Equatable {
    var serial = ""
    var user: Int? = nil
    var state: LockState = .unknown
    var online = false
    var awake = false
    var screenKnown = false
    var postUIVerifiedAt = 0.0
    var postUIStateChecked = false
    var postUIStateCheckSeconds = 0.0
    var observedAt = 0.0
    var coverBounds: UIBounds? = nil
    var coverIsVivo = false
    var coverIsFlyme = false
    var coverIsColorOS = false
    var coverIsHyperOS = false
    var colorOSRevealButton: UIBounds? = nil
    var coverWindow: String? = nil
    var focusResult = "not_queried"
    var focusSource = "none"
    var focusDisplayID: Int? = nil
    var hierarchyResult = "not_queried"
    var hierarchyStdoutEmpty = true
    var hierarchyStderrPresent = false
    var secure = false
    var bootComplete = false
    var reason = "unknown"
    var userUnlocked = false
    var progressPhase = "not_used"
    var target: PinTarget? = nil
}
// AOSP delegate dump contains cached values; a present monitor must be complete and scoped.
func delegateFields(_ text: String) -> [String: String]? {
    let lines = text.components(separatedBy: .newlines)
    func indent(_ line: String) -> Int { line.prefix(while: { $0 == " " }).count }
    func named(_ name: String) -> [Int] { lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == name } }
    let headers = named("KeyguardServiceDelegate")
    guard headers.count == 1 else { return nil }
    let start = headers[0]; let depth = indent(lines[start])
    let end = lines.indices.dropFirst(start + 1).first {
        !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty && indent(lines[$0]) <= depth
    } ?? lines.count
    var fields: [String: String] = [:]
    for line in lines[(start + 1)..<end] where indent(line) == depth + 2 {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        if ["showing", "inputRestricted", "occluded", "secure", "screenState", "interactiveState", "bootCompleted", "currentUser"].contains(parts[0]) {
            guard fields[parts[0]] == nil else { return nil }; fields[parts[0]] = parts[1]
        }
    }
    let monitors = named("KeyguardStateMonitor")
    guard monitors.count <= 1 else { return nil }
    if let monitor = monitors.first {
        guard monitor > start, monitor < end, indent(lines[monitor]) == depth + 2 else { return nil }
        let monitorEnd = lines.indices.dropFirst(monitor + 1).first {
            !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty && indent(lines[$0]) <= depth + 2
        } ?? lines.count
        for line in lines[(monitor + 1)..<min(monitorEnd, end)] where indent(line) == depth + 4 {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if ["mCurrentUserId", "mIsShowing", "mInputRestricted"].contains(parts[0]) {
                let key = "monitor." + parts[0]
                guard fields[key] == nil else { return nil }; fields[key] = parts[1]
            }
        }
        guard fields["monitor.mCurrentUserId"] == "0",
              ["true", "false"].contains(fields["monitor.mIsShowing"] ?? ""),
              fields["monitor.mIsShowing"] == fields["monitor.mInputRestricted"] else { return nil }
        fields["monitor.present"] = "true"
    }
    return fields
}
func parseState(serial: String, userText: String, policyText: String) -> Snapshot {
    var s = Snapshot(); s.serial = serial; s.online = true
    let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard u == "0" else { s.reason = "primary_user_only_or_unknown"; return s }
    s.user = 0
    guard let f = delegateFields(policyText),
          f["currentUser"] == "0" || (f["currentUser"] == "-10000" && f["monitor.present"] == "true"),
          ["true", "false"].contains(f["showing"] ?? ""),
          ["true", "false"].contains(f["inputRestricted"] ?? ""), f["occluded"] == "false",
          ["true", "false"].contains(f["secure"] ?? "") else {
        s.reason = "keyguard_ambiguous"; return s
    }
    let showing = f["monitor.present"] == "true" ? f["monitor.mIsShowing"] : f["showing"]
    let restricted = f["monitor.present"] == "true" ? f["monitor.mInputRestricted"] : f["inputRestricted"]
    guard showing == restricted else { s.reason = "keyguard_ambiguous"; return s }
    s.awake = f["screenState"] == "SCREEN_STATE_ON" && f["interactiveState"] == "INTERACTIVE_STATE_AWAKE"
    s.screenKnown = s.awake || (f["screenState"] == "SCREEN_STATE_OFF" && f["interactiveState"] == "INTERACTIVE_STATE_SLEEP")
    s.bootComplete = f["bootCompleted"] == "true"
    s.secure = f["secure"] == "true"
    s.state = showing == "true" ? .locked : .unlocked
    guard s.screenKnown else { s.reason = "screen_state_unknown"; return s }
    s.reason = "observed"
    return s
}
struct UIBounds: Equatable {
    let x1: Int; let y1: Int; let x2: Int; let y2: Int
    var center: (Int, Int) { ((x1 + x2) / 2, (y1 + y2) / 2) }
    func overlaps(_ b: UIBounds) -> Bool { x1 < b.x2 && x2 > b.x1 && y1 < b.y2 && y2 > b.y1 }
    func contains(_ b: UIBounds) -> Bool { x1 <= b.x1 && y1 <= b.y1 && x2 >= b.x2 && y2 >= b.y2 }
}
func uiBounds(_ text: String) -> UIBounds? {
    guard text.range(of: #"^\[\d{1,5},\d{1,5}\]\[\d{1,5},\d{1,5}\]$"#, options: .regularExpression) != nil else { return nil }
    let v = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    guard v.count == 4, v[0] < v[2], v[1] < v[3], v[2] <= 16384, v[3] <= 16384 else { return nil }
    return UIBounds(x1: v[0], y1: v[1], x2: v[2], y2: v[3])
}
struct FlymeProgressHeader: Equatable { let sequence: Int; let count: Int; let error: Int; let length: Int }
func progressHeader(_ text: String, sequence: Int) -> FlymeProgressHeader? {
    let parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 5, parts[0] == "__AU_FLYME_V1__",
          let seq = Int(parts[1]), seq == sequence, (1...20).contains(seq), String(seq) == parts[1],
          let count = Int(parts[2]), (0...4).contains(count), String(count) == parts[2],
          let error = Int(parts[3]), (0...7).contains(error), String(error) == parts[3],
          let length = Int(parts[4]), (0...262144).contains(length), String(length) == parts[4],
          error == 0 || length == 0 else { return nil }
    return FlymeProgressHeader(sequence: seq, count: count, error: error, length: length)
}
func flymeMaskedProgress(_ text: String, observedCount: Int?) -> Int? {
    guard text.count <= 4, text.allSatisfy({ $0 == "•" }) else { return nil }
    guard let observedCount else { return text.count }
    guard (1...4).contains(observedCount), text.isEmpty || text.count == observedCount else { return nil }
    return observedCount
}
func freshFlymeInputProof(_ s: Snapshot, expected: Int, now: Double) -> Bool {
    preparationGate(s) == "eligible" && s.awake && s.focusResult == "focus_identity_verified" && s.focusDisplayID == 0 &&
        s.postUIStateChecked && s.postUIVerifiedAt >= s.observedAt && s.observedAt > 0 && now >= s.postUIVerifiedAt && now - s.observedAt <= 2 &&
        s.target?.mode == .flymeFour && s.target?.count == expected && s.target?.keys.count == 10
}
enum PinMode { case aosp, vivoSix, flymeFour, colorOSSix, hyperos }
func flymeTouchKeys(screen: UIBounds, local: UIBounds) -> [Int: UIBounds]? {
    guard local.x1 == 0, local.y1 == 0, local.x2 == screen.x2 - screen.x1,
          local.y2 == screen.y2 - screen.y1 else { return nil }
    // Exact audited zero-padding keypad: three columns, four rows, circular hit radius.
    let width = Float(local.x2) / 3, height = Float(local.y2) / 4
    let radius = width * 0.6 / 2
    var keys: [Int: UIBounds] = [:]
    for digit in 0...9 {
        let index = digit == 0 ? 10 : digit - 1, row = index / 3, column = index % 3
        let rect = UIBounds(x1: screen.x1 + Int(Float(column) * width), y1: screen.y1 + Int(Float(row) * height),
                            x2: screen.x1 + Int(Float(column + 1) * width), y2: screen.y1 + Int(Float(row + 1) * height))
        let point = rect.center
        guard rect.x1 < rect.x2, rect.y1 < rect.y2, screen.contains(rect) else { return nil }
        var hits: [Int] = []
        for cell in 0..<12 {
            let dx = Float(point.0 - screen.x1) - (Float(cell % 3) * width + width / 2)
            let dy = Float(point.1 - screen.y1) - (Float(cell / 3) * height + height / 2)
            if dx * dx + dy * dy < radius * radius { hits.append(cell) }
        }
        guard hits == [index] else { return nil }
        keys[digit] = rect
    }
    return keys
}
struct PinTarget: Equatable {
    let window: String; let field: String; let count: Int
    var mode: PinMode = .aosp
    var keys: [Int: UIBounds] = [:]
    var placeholder: UIBounds? = nil
}
func explicitEnteredCount(_ description: String) -> Int? {
    let re = try! NSRegularExpression(pattern: #"(?:已输入|输入了|entered)\s*(\d{1,2})\s*(?:位|个|digits?)"#)
    let matches = re.matches(in: description, range: NSRange(description.startIndex..., in: description))
    guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: description),
          let count = Int(description[range]), (0...6).contains(count) else { return nil }
    return count
}
final class PinXML: NSObject, XMLParserDelegate {
    var targets: [(String, Int)] = []; var bad = false
    var cover = false; var pinPresent = false
    var rectangles: [String: UIBounds] = [:]
    var stack: [String] = []; var seen: [String: Int] = [:]
    var vivoTarget: (String, Int)? = nil; var harmlessFocus = 0
    var flymeTarget: (String, Int)? = nil
    var flymeFailure = "not_observed"
    var flymeInvalid = false
    var verifiedFlymeProgressCount: Int? = nil
    let flymeChain = ["keyguard_bouncer_container", "keyguard_host_view", "keyguard_security_container", "view_flipper", "mz_keyguard_pin_view", "keyguard_bouncer_frame", "keyguard_bouncer_rl", "inputBox"]
    var flymeNodes: [String: Int] = [:]
    var flymeRectangles: [String: UIBounds] = [:]
    var flymeKeyboardLocal: UIBounds? = nil
    var hyperosField: (String, Int)? = nil
    var hyperosNodes: [String: Int] = [:]
    var hyperosRects: [String: UIBounds] = [:]
    var hyperosKeys: [Int: UIBounds] = [:]
    var hyperosDeleteClickable = false
    var hyperosDeleteExtras: [UIBounds] = []
    var hyperosInvalid = false
    var hyperosFailure = "not_observed"
    func hyperosKeyDigit(_ id: String) -> Int? {
        guard id.count == 4, id.hasPrefix("key"), let digit = Int(id.dropFirst(3)), id == "key\(digit)" else { return nil }
        return digit
    }
    func recordHyperOS(_ id: String, _ a: [String: String], _ ancestors: [String]) {
        func bounds() -> UIBounds? { uiBounds(a["bounds"] ?? "") }
        func plain() -> Bool {
            a["package"] == "com.android.systemui" && a["enabled"] == "true" && a["password"] == "false"
        }
        func reject(_ reason: String, focusedIsBad: Bool = false) {
            hyperosInvalid = true; hyperosFailure = reason
            if focusedIsBad || a["focused"] == "true" { bad = true }
        }
        if id == "keyguard_bouncer_container" {
            guard plain(), a["class"] == "android.widget.FrameLayout", a["focused"] == "false", a["clickable"] == "false", let rect = bounds() else { return }
            hyperosNodes[id, default: 0] += 1; hyperosRects[id] = rect; return
        }
        if id == "keyguard_security_container" {
            guard ancestors.last == "keyguard_bouncer_container", hyperosNodes["keyguard_bouncer_container"] == 1,
                  plain(), a["class"] == "android.view.ViewGroup", a["focused"] == "false", a["clickable"] == "false", let rect = bounds() else { return }
            hyperosNodes[id, default: 0] += 1; hyperosRects[id] = rect; return
        }
        if id == "view_flipper" {
            guard ancestors.last == "keyguard_security_container", hyperosNodes["keyguard_security_container"] == 1,
                  plain(), a["class"] == "android.widget.ViewFlipper", a["focused"] == "false", a["clickable"] == "false", let rect = bounds() else { return }
            hyperosNodes[id, default: 0] += 1; hyperosRects[id] = rect; return
        }
        if id == "keyguard_pin_view" {
            guard ancestors.last == "view_flipper", hyperosNodes["view_flipper"] == 1,
                  plain(), a["class"] == "android.widget.LinearLayout", a["focused"] == "false", a["clickable"] == "false", let rect = bounds() else {
                if ancestors.last == "view_flipper" { reject("node_attributes") }
                return
            }
            hyperosNodes[id, default: 0] += 1; hyperosRects[id] = rect; return
        }
        if id == "pin_container" {
            guard ancestors.last == "keyguard_pin_view", hyperosNodes["keyguard_pin_view"] == 1,
                  plain(), a["class"] == "android.widget.LinearLayout", a["focused"] == "false", a["clickable"] == "false", let rect = bounds() else {
                if ancestors.contains("keyguard_pin_view") { reject("node_attributes") }
                return
            }
            hyperosNodes[id, default: 0] += 1; hyperosRects[id] = rect; return
        }
        if id == "keyguard_selector_fade_container" {
            guard ancestors.last == "pin_container", hyperosNodes["pin_container"] == 1,
                  plain(), a["class"] == "android.widget.LinearLayout", a["focused"] == "false", a["clickable"] == "false", let rect = bounds() else { return }
            hyperosNodes[id, default: 0] += 1; hyperosRects[id] = rect; return
        }
        let inPin = ancestors.contains("keyguard_pin_view") && hyperosNodes["keyguard_pin_view"] == 1
        if id == "delete_container" {
            guard inPin, ancestors.contains("pin_container"), hyperosNodes["pin_container"] == 1,
                  plain(), a["class"] == "android.widget.FrameLayout", a["focused"] == "false",
                  a["clickable"] == "true" || a["focusable"] == "false", let rect = bounds() else {
                if inPin { reject("delete_conflict", focusedIsBad: true) }
                return
            }
            hyperosNodes[id, default: 0] += 1; hyperosRects[id] = rect
            if a["clickable"] == "true" { hyperosDeleteClickable = true }
            return
        }
        if ancestors.contains("delete_container"), a["clickable"] == "true" {
            guard inPin, let rect = bounds(), hyperosRects["delete_container"]?.contains(rect) == true else {
                if inPin { reject("delete_conflict") }
                return
            }
            hyperosDeleteClickable = true; hyperosDeleteExtras.append(rect); return
        }
        if let digit = hyperosKeyDigit(id) {
            guard inPin, hyperosKeys[digit] == nil, ancestors.contains("pin_container"),
                  plain(), a["class"] == "android.view.ViewGroup", a["clickable"] == "true", a["focusable"] == "true", a["focused"] == "false",
                  let rect = bounds() else {
                if inPin { reject("key_geometry", focusedIsBad: true) }
                return
            }
            hyperosNodes[id, default: 0] += 1; hyperosKeys[digit] = rect
        }
    }
    var validHyperOS: Bool {
        guard !hyperosInvalid, let field = hyperosField, hyperosNodes["pinEntry"] == 1, hyperosNodes["delete_container"] == 1,
              hyperosNodes["emergency_call_button"] == 1, hyperosNodes["keyguard_selector_fade_container"] == 1,
              hyperosKeys.count == 10, (0...9).allSatisfy({ hyperosKeys[$0] != nil }) else { return false }
        let chain = ["keyguard_bouncer_container", "keyguard_security_container", "view_flipper", "keyguard_pin_view", "pin_container"]
        guard chain.allSatisfy({ hyperosNodes[$0] == 1 }),
              let bouncer = hyperosRects["keyguard_bouncer_container"], let security = hyperosRects["keyguard_security_container"],
              let flipper = hyperosRects["view_flipper"], let pinView = hyperosRects["keyguard_pin_view"],
              let area = hyperosRects["pin_container"], let fade = hyperosRects["keyguard_selector_fade_container"],
              let fieldBounds = uiBounds(field.0), let delete = hyperosRects["delete_container"],
              let emergency = hyperosRects["emergency_call_button"] else { return false }
        guard bouncer.contains(security), security.contains(flipper), flipper.contains(pinView), pinView.contains(area),
              area.contains(fade), fade.contains(emergency), area.contains(fieldBounds), area.contains(delete),
              !fieldBounds.overlaps(delete), !fieldBounds.overlaps(emergency), !delete.overlaps(emergency) else { return false }
        if field.1 == 0 { guard !hyperosDeleteClickable else { return false } }
        else { guard hyperosDeleteClickable else { return false } }
        for extra in hyperosDeleteExtras {
            guard delete.contains(extra), !extra.overlaps(fieldBounds), !extra.overlaps(emergency) else { return false }
            for key in hyperosKeys.values where extra.overlaps(key) { return false }
        }
        for digit in 0...9 {
            guard let key = hyperosKeys[digit], area.contains(key), !key.overlaps(fieldBounds), !key.overlaps(delete), !key.overlaps(emergency), !key.overlaps(fade) else { return false }
            for other in 0..<digit { guard !key.overlaps(hyperosKeys[other]!) else { return false } }
        }
        return true
    }
    var flymeCover: Bool {
        guard !flymeInvalid, ["keyguard_background_frame", "keyguard_header", "keyguard_selector_fade_container"].allSatisfy({ flymeNodes[$0] == 1 }),
              let area = flymeRectangles["keyguard_background_frame"], let header = flymeRectangles["keyguard_header"],
              let footer = flymeRectangles["keyguard_selector_fade_container"] else { return false }
        return area.contains(header) && area.contains(footer) && !header.overlaps(footer)
    }
    var validFlyme: Bool {
        guard !flymeInvalid, let target = flymeTarget, flymeChain.allSatisfy({ flymeNodes[$0] == 1 }), flymeNodes["passwordEntry"] == 1,
              flymeNodes["lockPattern"] == 1, let field = uiBounds(target.0), let area = flymeRectangles["mz_keyguard_pin_view"],
              let keyboard = flymeRectangles["lockPattern"], let local = flymeKeyboardLocal,
              flymeTouchKeys(screen: keyboard, local: local) != nil, area.contains(keyboard), !field.overlaps(keyboard),
              flymeChain.allSatisfy({ flymeRectangles[$0]?.contains(field) == true }) else { return false }
        // The OEM sets delete visible on append; empty accessibility text must not contradict it.
        if target.1 == 0 { return flymeNodes["delete"] == nil }
        guard flymeNodes["delete"] == 1, let delete = flymeRectangles["delete"] else { return false }
        return area.contains(delete) && !keyboard.overlaps(delete)
    }
    let prefix = "com.android.systemui:id/"
    var hasVivoCover: Bool {
        ["vivo_keyguard_overlay", "vivo_keyguard_host_container", "com.vivo.systemuiplugin:id/keyguard_os5"].contains { seen[$0] != nil }
    }
    var vivoCover: Bool {
        ["vivo_keyguard_overlay", "vivo_keyguard_host_container", "com.vivo.systemuiplugin:id/keyguard_os5"].allSatisfy { seen[$0] == 1 }
    }
    var validVivo: Bool {
        guard let target = vivoTarget, harmlessFocus == 0 else { return false }
        let ids = ["keyguard_bouncer_container", "keyguard_security_container", "vivo_pin_view", "vivo_pin_keyboard"] +
            (1...6).map { "password\($0)bg" } + (0...9).map { "VivoPinkey\($0)" }
        return ids.allSatisfy { seen[$0] == 1 } && (1...6).allSatisfy {
            let occurrences = seen["password\($0)"] ?? 0
            return occurrences == 1 || ($0 <= target.1 && occurrences == 0)
        }
    }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard element == "node" else { return }
        let raw = a["resource-id"] ?? ""; let id = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        let ancestors = stack; stack.append(id)
        if a["password"] == "true" { pinPresent = true }
        recordHyperOS(id, a, ancestors)
        if id == "pinEntry", a["class"] == "com.android.keyguard.PasswordTextView" {
            pinPresent = true
            hyperosNodes["pinEntry", default: 0] += 1
            let chain = ["keyguard_bouncer_container", "keyguard_security_container", "view_flipper", "keyguard_pin_view", "pin_container"]
            guard hyperosNodes["pinEntry"] == 1, a["package"] == "com.android.systemui", a["enabled"] == "true",
                  a["password"] == "true", a["focused"] == "true", a["focusable"] == "true", a["clickable"] == "false",
                  chain.allSatisfy({ ancestors.contains($0) }), chain.allSatisfy({ hyperosNodes[$0] == 1 }),
                  let text = a["text"], text.count <= 16, text.allSatisfy({ $0 == "•" }),
                  let bounds = a["bounds"], uiBounds(bounds) != nil else {
                bad = true; hyperosInvalid = true; hyperosFailure = "field_or_mask"; return
            }
            hyperosField = (bounds, text.count); return
        }
        if id == "emergency_call_button", ancestors.contains("keyguard_pin_view"), hyperosNodes["keyguard_pin_view"] == 1 {
            hyperosNodes[id, default: 0] += 1
            guard hyperosNodes[id] == 1, a["package"] == "com.android.systemui", a["class"] == "android.widget.Button",
                  a["enabled"] == "true", a["password"] == "false", a["clickable"] == "true", a["focusable"] == "true",
                  ancestors.contains("pin_container"), ancestors.contains("keyguard_selector_fade_container"),
                  let rect = uiBounds(a["bounds"] ?? "") else {
                bad = true; hyperosInvalid = true; hyperosFailure = "unexpected_focus"; return
            }
            hyperosRects[id] = rect; return
        }
        let flymeOnly = ["keyguard_host_view", "view_flipper", "mz_keyguard_pin_view", "keyguard_bouncer_frame", "keyguard_bouncer_rl", "inputBox", "passwordEntry", "lockPattern", "delete", "keyguard_background_frame", "keyguard_selector_fade_container"]
        let flymeSecurity = id == "keyguard_security_container" && a["class"] == "android.widget.FrameLayout" && ancestors.last == "keyguard_host_view"
        if raw.hasPrefix(prefix), flymeOnly.contains(id) || flymeSecurity || id == "keyguard_bouncer_container" || id == "keyguard_header" {
            func rejectFlyme(_ reason: String) {
                flymeInvalid = true; flymeFailure = reason
                if id == "passwordEntry" || id == "mz_keyguard_pin_view" || ancestors.contains("mz_keyguard_pin_view") || a["focused"] == "true" { bad = true }
            }
            flymeNodes[id, default: 0] += 1
            if let rect = uiBounds(a["bounds"] ?? "") { flymeRectangles[id] = rect }
            if id == "keyguard_header", a["package"] != "com.android.systemui" || a["class"] != "android.widget.RelativeLayout" || a["enabled"] != "true" || a["password"] != "false" || a["focused"] != "false" || a["clickable"] != "false" { flymeInvalid = true }
            if flymeOnly.contains(id) || flymeSecurity {
                let cls: String
                switch id {
                case "passwordEntry": cls = "android.widget.EditText"
                case "mz_keyguard_pin_view": cls = "android.widget.LinearLayout"
                case "view_flipper": cls = "android.widget.ViewFlipper"
                case "inputBox", "keyguard_bouncer_rl": cls = "android.widget.RelativeLayout"
                case "lockPattern": cls = "android.view.View"
                case "delete": cls = "android.widget.ImageView"
                default: cls = "android.widget.FrameLayout"
                }
                guard a["package"] == "com.android.systemui", a["class"] == cls, a["enabled"] == "true", flymeRectangles[id] != nil,
                      a["password"] == (id == "passwordEntry" ? "true" : "false") else { rejectFlyme("node_attributes"); return }
                if let index = flymeChain.firstIndex(of: id), index > 0 {
                    guard Array(ancestors.suffix(index)) == Array(flymeChain.prefix(index)) else { rejectFlyme("ancestry"); return }
                }
                if id == "passwordEntry" {
                    pinPresent = true
                    guard Array(ancestors.suffix(flymeChain.count)) == flymeChain,
                          a["focused"] == "true", a["focusable"] == "true", a["clickable"] == "false",
                          a["editable"] == "true", a["input-type"] == "16", a["max-text-length"] == "-1",
                          let text = a["text"], text.count <= 4, text.allSatisfy({ $0 == "•" }) else {
                        rejectFlyme("field_or_mask"); return
                    }
                    guard let count = flymeMaskedProgress(text, observedCount: verifiedFlymeProgressCount) else { rejectFlyme("progress_mask_conflict"); return }
                    flymeTarget = (a["bounds"]!, count); flymeFailure = "structure_or_empty_conflict"; return
                }
                guard a["focused"] == "false" else { rejectFlyme("unexpected_focus"); return }
                if ["lockPattern", "delete"].contains(id) {
                    guard ancestors.contains("mz_keyguard_pin_view"), ancestors.contains("keyguard_security_container") else { rejectFlyme("ancestry"); return }
                    if id == "lockPattern" {
                        guard Array(ancestors.suffix(flymeChain.count - 1)) == Array(flymeChain.dropLast()),
                              let local = uiBounds(a["bounds-parent"] ?? "") else { rejectFlyme("keyboard_geometry"); return }
                        flymeKeyboardLocal = local
                    }
                } else if a["clickable"] != "false" { rejectFlyme("node_attributes"); return }
                return
            }
        }
        let known = ["keyguard_bouncer_container", "keyguard_security_container", "vivo_pin_view", "vivo_pin_keyboard", "vivo_keyguard_overlay", "vivo_keyguard_host_container", "com.vivo.systemuiplugin:id/keyguard_os5"] +
            (1...6).flatMap { ["password\($0)", "password\($0)bg"] } + (0...9).map { "VivoPinkey\($0)" }
        if known.contains(id) {
            seen[id, default: 0] += 1
            guard let rect = uiBounds(a["bounds"] ?? "") else { bad = true; return }; rectangles[id] = rect
            guard a["package"] == "com.android.systemui", a["enabled"] == "true", a["password"] == "false" else { bad = true; return }
            let cls: String
            switch id {
            case "keyguard_security_container": cls = "android.view.ViewGroup"
            case "vivo_pin_view", "com.vivo.systemuiplugin:id/keyguard_os5": cls = "android.widget.RelativeLayout"
            case "vivo_pin_keyboard": cls = "android.widget.LinearLayout"
            default: cls = id.hasPrefix("VivoPinkey") ? "android.view.ViewGroup" : "android.widget.FrameLayout"
            }
            guard a["class"] == cls else { bad = true; return }
            if ["vivo_keyguard_overlay", "vivo_keyguard_host_container", "com.vivo.systemuiplugin:id/keyguard_os5"].contains(id),
               a["clickable"] != "false" || a["focused"] != "false" { bad = true; return }
            if id == "keyguard_security_container", !ancestors.contains("keyguard_bouncer_container") { bad = true }
            if id == "vivo_pin_view" {
                pinPresent = true
                guard ancestors.contains("keyguard_security_container"), ancestors.contains("keyguard_bouncer_container"),
                      a["focused"] == "true", a["focusable"] == "true", a["clickable"] == "false", a["text"] == "",
                      let count = explicitEnteredCount(a["content-desc"] ?? ""), let bounds = a["bounds"],
                      bounds.range(of: #"^\[\d+,\d+\]\[\d+,\d+\]$"#, options: .regularExpression) != nil else { bad = true; return }
                vivoTarget = (bounds, count); return
            }
            if id == "vivo_pin_keyboard" || id.hasPrefix("password") || id.hasPrefix("VivoPinkey") {
                guard ancestors.contains("vivo_pin_view"), a["focused"] == "false" else { bad = true; return }
                if id.hasPrefix("VivoPinkey") {
                    guard ancestors.contains("vivo_pin_keyboard"), a["clickable"] == "true", a["focusable"] == "true" else { bad = true; return }
                } else if a["clickable"] != "false" { bad = true }
            }
        }
        if a["package"] == "com.android.systemui" {
            if raw == prefix + "pinEntry" { pinPresent = true }
            if raw == prefix + "keyguard_status_view" { cover = true }
            if raw == prefix + "keyguard_header", a["class"] == "android.widget.RelativeLayout",
               a["enabled"] == "true", a["password"] == "false", a["focused"] == "false" { cover = true }
        }
        guard a["focused"] == "true" else { return }
        if a["package"] == "com.android.systemui", raw == "com.vivo.systemuiplugin:id/lunar_info_first_line",
           a["class"] == "android.widget.TextView", a["password"] == "false", a["clickable"] == "false", a["enabled"] == "true" {
            harmlessFocus += 1; return
        }
        guard a["package"] == "com.android.systemui", raw == prefix + "pinEntry",
              a["class"] == "android.widget.EditText", a["password"] == "true", a["enabled"] == "true",
              a["focusable"] == "true", let text = a["text"], text.allSatisfy({ $0 == "•" }),
              let bounds = a["bounds"], bounds.range(of: #"^\[\d+,\d+\]\[\d+,\d+\]$"#, options: .regularExpression) != nil else { bad = true; return }
        targets.append((bounds, text.count))
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "node" { stack.removeLast() }
    }
}
func parseHierarchy(_ xml: String, flymeProgressCount: Int? = nil) -> PinXML? {
    guard let start = xml.range(of: "<?xml"), let end = xml.range(of: "</hierarchy>"), start.lowerBound < end.upperBound else { return nil }
    let fragment = String(xml[start.lowerBound..<end.upperBound])
    guard !fragment.contains("<!DOCTYPE"), !fragment.contains("<!ENTITY") else { return nil }
    let delegate = PinXML(); delegate.verifiedFlymeProgressCount = flymeProgressCount; let parser = XMLParser(data: Data(fragment.utf8)); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    return parser.parse() ? delegate : nil
}
func pinTarget(xml: String, windowText: String) -> PinTarget? {
    guard let delegate = parseHierarchy(xml) else { return nil }
    return pinTarget(delegate: delegate, windowText: windowText)
}
func pinTarget(delegate: PinXML, windowText: String) -> PinTarget? {
    let lines = windowText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("mCurrentFocus=") }
    guard !delegate.bad, lines.count == 1, lines[0].range(of: #"^mCurrentFocus=Window\{(?:com\.android\.systemui:)?[0-9a-f]+ u0 [^{}\r\n]+\}$"#, options: .regularExpression) != nil else { return nil }
    if delegate.validFlyme, delegate.targets.isEmpty, delegate.vivoTarget == nil, delegate.harmlessFocus == 0, let target = delegate.flymeTarget {
        guard let keyboard = delegate.flymeRectangles["lockPattern"], let local = delegate.flymeKeyboardLocal,
              let keys = flymeTouchKeys(screen: keyboard, local: local) else { return nil }
        return PinTarget(window: lines[0], field: target.0, count: target.1, mode: .flymeFour, keys: keys)
    }
    guard delegate.flymeTarget == nil, delegate.flymeNodes["mz_keyguard_pin_view"] == nil else { return nil }
    if delegate.validVivo, delegate.targets.isEmpty, let target = delegate.vivoTarget {
        guard let area = uiBounds(target.0), let keyboard = delegate.rectangles["vivo_pin_keyboard"], area.contains(keyboard),
              let placeholder = delegate.rectangles["password1bg"], area.contains(placeholder) else { return nil }
        var keys: [Int: UIBounds] = [:]
        for digit in 0...9 {
            guard let rect = delegate.rectangles["VivoPinkey\(digit)"], keyboard.contains(rect) else { return nil }; keys[digit] = rect
        }
        for i in 1...6 {
            guard let background = delegate.rectangles["password\(i)bg"], area.contains(background),
                  !keyboard.overlaps(background) else { return nil }
            if let slot = delegate.rectangles["password\(i)"] { guard slot == background else { return nil } }
        }
        for i in 0...9 { for j in 0..<i { guard !keys[i]!.overlaps(keys[j]!) else { return nil } } }
        return PinTarget(window: lines[0], field: target.0, count: target.1, mode: .vivoSix, keys: keys, placeholder: placeholder)
    }
    guard delegate.vivoTarget == nil, delegate.harmlessFocus == 0 else { return nil }
    if (delegate.hyperosNodes["keyguard_pin_view"] ?? 0) > 0 {
        guard delegate.validHyperOS, delegate.targets.isEmpty, let field = delegate.hyperosField else { return nil }
        return PinTarget(window: lines[0], field: field.0, count: field.1, mode: .hyperos, keys: delegate.hyperosKeys, placeholder: uiBounds(field.0))
    }
    guard delegate.targets.count == 1 else { return nil }
    return PinTarget(window: lines[0], field: delegate.targets[0].0, count: delegate.targets[0].1)
}
func preparationGate(_ s: Snapshot) -> String {
    guard s.reason == "observed", s.online, s.user == 0 else { return s.reason == "observed" ? "device_user_unverified" : s.reason }
    guard s.bootComplete, s.userUnlocked else { return "boot_first_unlock_unsupported" }
    if s.state == .unlocked { return "already_unlocked" }
    guard s.state == .locked, s.secure, s.screenKnown else { return "secure_keyguard_unverified" }
    return "eligible"
}
func decision(_ s: Snapshot) -> String {
    let gate = preparationGate(s)
    guard gate == "eligible" else { return gate }
    guard s.awake else { return "preparation_needed_wake" }
    if let target = s.target { return target.count == 0 ? "ready" : "pin_field_not_empty" }
    return s.coverWindow == nil ? "secure_empty_pin_target_unverified" : "preparation_needed_pin_page"
}
struct Preparation {
    var snapshot: Snapshot
    var result = "not_attempted"
    var wakeAttempted = false
    var presentationAttempted = false
    var attempted: Bool { wakeAttempted || presentationAttempted }
}
// Same authorization covers at most one wake-only event and one verified SystemUI Space event.
func prepare(_ initial: Snapshot, authorized: Bool, observe: () -> Snapshot,
             wake: () -> Bool, afterWake: () -> Snapshot,
             present: () -> Bool, afterPresent: () -> Snapshot) -> Preparation {
    var p = Preparation(snapshot: initial)
    guard authorized else { p.result = "authorization_required"; return p }
    let gate = preparationGate(initial)
    guard gate == "eligible" else { p.result = gate; return p }
    var current = observe(); p.snapshot = current
    guard consistent(initial, current) else { p.result = "preparation_state_changed"; return p }
    if preparationGate(current) == "already_unlocked" { p.result = "already_unlocked"; return p }
    guard preparationGate(current) == "eligible" else { p.result = "preparation_state_changed"; return p }
    if !current.awake {
        p.wakeAttempted = true
        guard wake() else { p.result = "wake_command_failed_no_retry"; return p }
        current = afterWake(); p.snapshot = current
        guard consistent(initial, current), current.reason == "observed", current.awake else { p.result = "wake_unconfirmed_no_retry"; return p }
        if preparationGate(current) == "already_unlocked" { p.result = "already_unlocked"; return p }
        guard preparationGate(current) == "eligible" else { p.result = "post_wake_state_changed"; return p }
    }
    if decision(current) == "ready" { p.result = "ready"; return p }
    guard current.target == nil, let window = current.coverWindow else { p.result = decision(current); return p }
    let fresh = observe(); p.snapshot = fresh
    guard consistent(initial, fresh), preparationGate(fresh) == "eligible", fresh.awake,
          fresh.coverWindow == window, fresh.target == nil else { p.result = "presentation_focus_changed"; return p }
    p.presentationAttempted = true
    guard present() else { p.result = "presentation_command_failed_no_retry"; return p }
    current = afterPresent(); p.snapshot = current
    guard consistent(initial, current), decision(current) == "ready", current.target?.window == window else {
        p.result = "pin_page_unconfirmed_no_retry"; return p
    }
    p.result = "ready"; return p
}
enum UIReuse { case reuse, refresh, blocked }
func uiReuse(_ previous: Snapshot, _ current: Snapshot, window: String, now: Double) -> UIReuse {
    guard consistent(previous, current), current.reason == "observed", current.state == .locked,
          current.awake, current.secure, previous.reason == "observed", previous.state == .locked,
          previous.awake, previous.secure, previous.coverWindow == window || previous.target?.window == window,
          previous.observedAt > 0, now >= previous.observedAt else { return .blocked }
    if previous.target != nil { return .refresh }
    return now - previous.observedAt <= 2 ? .reuse : .refresh
}
func existingAuthorizationEligible(_ s: Snapshot) -> Bool {
    validSerial(s.serial) && s.online && s.reason == "observed" && s.state == .unlocked && s.awake && s.secure &&
        s.user == 0 && s.userUnlocked && s.bootComplete
}
func consistent(_ a: Snapshot, _ b: Snapshot) -> Bool {
    a.online && b.online && a.serial == b.serial && a.user == 0 && b.user == 0 && b.userUnlocked && b.bootComplete
}
enum CredentialStage: String { case interaction = "set_user_interaction", query = "copy_matching", returnedType = "returned_type", pinFormat = "numeric_pin_format", success = "read_success" }
struct CredentialMetadata {
    let stage: CredentialStage
    let status: Int32
    let interactive: Bool
    var json: [String: Any] { ["stage": stage.rawValue, "osStatus": status, "mode": interactive ? "interactive" : "noninteractive"] }
}
struct CredentialRead {
    var pin: Data?
    let metadata: CredentialMetadata
}
func readCredential(interactive: Bool, setInteraction: (Bool) -> Int32, query: () -> (Int32, Any?)) -> CredentialRead {
    defer { if interactive { _ = setInteraction(false) } }
    func failed(_ stage: CredentialStage, _ status: Int32) -> CredentialRead {
        CredentialRead(pin: nil, metadata: CredentialMetadata(stage: stage, status: status, interactive: interactive))
    }
    let interactionStatus = setInteraction(interactive)
    guard interactionStatus == 0 else { return failed(.interaction, interactionStatus) }
    let (status, item) = query()
    var data = item as? Data
    guard status == 0 else {
        if data != nil { data!.resetBytes(in: 0..<data!.count) }
        return failed(.query, status)
    }
    guard data != nil else { return failed(.returnedType, status) }
    guard validPIN(data!) else {
        data!.resetBytes(in: 0..<data!.count)
        return failed(.pinFormat, status)
    }
    return CredentialRead(pin: data, metadata: CredentialMetadata(stage: .success, status: status, interactive: interactive))
}
struct ExistingAuthorization {
    let result: String
    var diagnostics: [CredentialMetadata] = []
    var proofScope = "not_verified"
}
func verifyExistingAuthorization(interactiveRead: () -> CredentialRead, noninteractiveRead: () -> CredentialRead) -> ExistingAuthorization {
    var first = interactiveRead()
    guard first.pin != nil else { return ExistingAuthorization(result: "credential_authorization_blocked", diagnostics: [first.metadata]) }
    first.pin!.resetBytes(in: 0..<first.pin!.count); first.pin = nil
    var second = noninteractiveRead()
    let success = second.pin != nil
    if second.pin != nil { second.pin!.resetBytes(in: 0..<second.pin!.count); second.pin = nil }
    return ExistingAuthorization(result: success ? "credential_authorized" : "credential_authorized_noninteractive_blocked",
        diagnostics: [first.metadata, second.metadata], proofScope: success ? "same_process_noninteractive_only" : "interactive_read_only")
}
func validPIN(_ data: Data) -> Bool { (4...16).contains(data.count) && data.allSatisfy { (48...57).contains($0) } }
enum InputResult { case refused, partial, submitted }
func pinInputMetadata(_ s: Snapshot, actions: Int, adbSucceeded: Int, now: Double) -> [String: Any] {
    let trusted = s.reason == "observed" && s.focusResult == "focus_identity_verified" && s.postUIStateChecked &&
        s.postUIVerifiedAt >= s.observedAt && s.observedAt > 0 && now >= s.postUIVerifiedAt && now - s.observedAt <= 2
    var result: [String: Any] = ["actionsAttempted": actions, "adbSucceeded": adbSucceeded, "reason": s.reason,
        "hierarchyResult": s.hierarchyResult, "lockState": s.state.rawValue, "awake": s.awake,
        "postUIStateChecked": s.postUIStateChecked, "sampleFresh": trusted]
    if s.progressPhase != "not_used" {
        result["phase"] = s.progressPhase
        result["samplePrecedesLastAction"] = s.progressPhase == "dispatch_adb_result_pre_input_sample"
    }
    if trusted, let target = s.target { result["observedEnteredCount"] = target.count }
    return result
}
// OEM keypad profiles auto-submit their final digit; never dispatch Enter for those modes.
func drivePIN(_ pin: Data, initial: Snapshot, observe: (Bool) -> Snapshot, send: (Int) -> Bool) -> InputResult {
    guard validPIN(pin), let target = initial.target, (target.mode != .vivoSix && target.mode != .colorOSSix) || pin.count == 6,
          target.mode != .flymeFour || pin.count == 4 else { return .refused }
    let autoSubmit = target.mode == .vivoSix || target.mode == .flymeFour || target.mode == .colorOSSix || target.mode == .hyperos
    var sent = false
    for index in 0...pin.count {
        let finalOEM = index == pin.count && autoSubmit
        let now = observe(finalOEM)
        guard consistent(initial, now), now.reason == "observed" else { return sent ? .partial : .refused }
        if index == pin.count && now.state == .unlocked { return .submitted }
        if finalOEM { return .partial }
        guard now.state == .locked, now.awake, now.secure, let field = now.target,
              field.window == target.window, field.field == target.field, field.mode == target.mode,
              field.count == index else { return sent ? .partial : .refused }
        let key = index == pin.count ? 66 : Int(pin[index] - 48) + 7
        sent = true
        guard send(key) else { return .partial }
    }
    return .submitted
}
func attempt(_ s: Snapshot, authorized: Bool, recheck: () -> Snapshot, read: () -> Bool,
             submit: () -> InputResult, confirm: () -> Snapshot) -> (String, Bool) {
    guard authorized else { return ("authorization_required", false) }
    let d = decision(s)
    guard d == "ready" else { return (d, false) }
    let fresh = recheck()
    guard consistent(s, fresh), decision(fresh) == "ready", s.target == fresh.target else { return ("state_changed_before_secret", false) }
    guard read() else { return ("credential_blocked", false) }
    let before = recheck()
    guard consistent(s, before), decision(before) == "ready", s.target == before.target else { return ("state_changed_before_input", false) }
    switch submit() {
    case .refused: return ("input_refused", false)
    case .partial: return ("partial_input_aborted_no_retry", true)
    case .submitted: break
    }
    let after = confirm()
    return (consistent(s, after) && after.reason == "observed" && after.state == .unlocked ? "unlocked_confirmed" : "confirmation_failed_no_retry", true)
}

func verifiedWindow(_ text: String, target: PinTarget, pid: String, uid: Int) -> Bool {
    let window = String(target.window.dropFirst("mCurrentFocus=".count))
    let sections = text.components(separatedBy: "Window #").filter { $0.components(separatedBy: .newlines).first?.contains(window) == true }
    guard sections.count == 1 else { return false }
    let block = sections[0]
    guard uid > 0, uid < 100000, Int(pid).map({ $0 > 0 }) == true else { return false }
    let owner = try! NSRegularExpression(pattern: #"\bmOwnerUid=(\d+)\b"#)
    let sessions = try! NSRegularExpression(pattern: #"mSession=Session\{[0-9a-f]+ (\d+):([^} ]+)\}"#)
    let types = try! NSRegularExpression(pattern: #"\bty=([^\s{}]*)"#)
    let ns = block as NSString; let range = NSRange(location: 0, length: ns.length)
    let owners = owner.matches(in: block, range: range)
    let session = sessions.matches(in: block, range: range)
    let roles = types.matches(in: block, range: range)
    guard owners.count == 1, session.count == 1, roles.count == 1,
          ns.substring(with: owners[0].range(at: 1)) == String(uid),
          ns.substring(with: session[0].range(at: 1)) == pid,
          ["NOTIFICATION_SHADE", "2040"].contains(ns.substring(with: roles[0].range(at: 1))) else { return false }
    let uidToken = ns.substring(with: session[0].range(at: 2))
    // Observed decimal and vivo u0a<full numeric UID>; never normalize unproven tokens.
    return uidToken == String(uid) || uidToken == "u0a\(uid)"

}

func coverHierarchy(_ xml: String, requireVivo: Bool = false) -> Bool {
    guard let delegate = parseHierarchy(xml) else { return false }
    return coverHierarchy(delegate, requireVivo: requireVivo)
}
func coverHierarchy(_ delegate: PinXML, requireVivo: Bool = false) -> Bool {
    delegate.cover && !delegate.pinPresent && !delegate.bad && (!requireVivo || delegate.vivoCover) &&
        (!delegate.hasVivoCover || delegate.vivoCover) &&
        (delegate.harmlessFocus == 0 || (delegate.harmlessFocus == 1 && delegate.vivoCover))
}
func vivoCoverBounds(_ xml: String) -> UIBounds? {
    guard let delegate = parseHierarchy(xml) else { return nil }
    return vivoCoverBounds(delegate)
}
func vivoCoverBounds(_ delegate: PinXML) -> UIBounds? {
    guard coverHierarchy(delegate), delegate.vivoCover, let area = delegate.rectangles["vivo_keyguard_host_container"],
          delegate.rectangles["vivo_keyguard_overlay"] == area, delegate.rectangles["com.vivo.systemuiplugin:id/keyguard_os5"] == area else { return nil }
    return area
}
func immediateCoverObservation(_ initial: Snapshot, _ current: Snapshot, now: Double) -> Bool {
    consistent(initial, current) && preparationGate(current) == "eligible" && current.awake &&
        current.target == nil && current.coverWindow != nil && current.focusResult == "focus_identity_verified" &&
        current.postUIStateChecked && current.postUIVerifiedAt >= current.observedAt && current.observedAt > 0 &&
        now >= current.postUIVerifiedAt && now - current.observedAt <= 2 &&
        (initial.coverWindow == nil || initial.coverWindow == current.coverWindow)
}
func activityEligible(_ s: Snapshot, authorized: Bool) -> Bool {
    authorized && decision(s) == "ready" && (s.target?.mode == .vivoSix || s.target?.mode == .hyperos) && s.target?.placeholder != nil
}
// Dispatch may reuse only the immutable full PIN snapshot returned by the first real recheck.
func immediateTrustedPinActivityObservation(_ s: Snapshot, serial: String, authorized: Bool, now: Double) -> Bool {
    guard s.serial == serial, validSerial(serial), activityEligible(s, authorized: authorized),
          s.focusResult == "focus_identity_verified", ["windows", "displays"].contains(s.focusSource), s.focusDisplayID == 0,
          s.hierarchyResult == "hierarchy_xml_parsed", !s.hierarchyStdoutEmpty, s.coverWindow == nil,
          s.postUIStateChecked, s.observedAt > 0, s.postUIVerifiedAt >= s.observedAt,
          now >= s.postUIVerifiedAt, now - s.observedAt <= 2,
          let target = s.target, let area = uiBounds(target.field), let placeholder = target.placeholder,
          placeholder.x1 < placeholder.x2, placeholder.y1 < placeholder.y2, area.contains(placeholder),
          target.window.range(of: #"^mCurrentFocus=Window\{(?:com\.android\.systemui:)?[0-9a-f]+ u0 [^{}\r\n]+\}$"#, options: .regularExpression) != nil,
          target.keys.count == 10, (0...9).allSatisfy({ target.keys[$0].map { !$0.overlaps(placeholder) } == true }) else { return false }
    return true
}
// Unknown screen transition may be sampled again; never permits an event or secret read.
func canSettleWake(_ initial: Snapshot, _ current: Snapshot) -> Bool {
    consistent(initial, current) && initial.userUnlocked && initial.bootComplete &&
    initial.state == .locked && current.state == .locked && initial.secure && current.secure &&
    ["observed", "screen_state_unknown"].contains(current.reason)
}


struct FocusObservation {
    var line: String? = nil
    var source = "none"
    var displayID: Int? = nil
    var result = "focus_unverified"
}
func focusObservation(windows: String, displays: String) -> FocusObservation {
    var r = FocusObservation()
    let direct = windows.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("mCurrentFocus=") }
    var scoped: [(String, Int)] = []
    var display: Int? = nil
    var depth = 0
    for line in displays.components(separatedBy: .newlines) {
        let text = line.trimmingCharacters(in: .whitespaces)
        let indent = line.prefix(while: { $0 == " " }).count
        if let range = text.range(of: #"^Display: mDisplayId=\d+"#, options: .regularExpression) {
            display = Int(text[range].split(separator: "=").last!); depth = indent
        } else if !text.isEmpty && indent < depth {
            // ColorOS prints exactly mIsDensityForced=true|false at column 0 inside an open display block.
            // A combined, malformed, or unrelated outdented line still ends that scope and cannot open one.
            let exactDensityBoolean = display != nil && text.range(of: #"^mIsDensityForced=(true|false)$"#, options: .regularExpression) != nil
            if !exactDensityBoolean { display = nil }
        }
        if text.hasPrefix("mCurrentFocus=") {
            guard let display else { r.result = "focus_display_unscoped"; return r }
            scoped.append((text, display))
        }
    }
    guard direct.count <= 1, scoped.count <= 1 else { r.result = "focus_ambiguous"; return r }
    if let d = direct.first, let scopedFocus = scoped.first, d != scopedFocus.0 { r.result = "focus_sources_conflict"; return r }
    guard let line = direct.first ?? scoped.first?.0 else { r.result = "focus_missing"; return r }
    guard scoped.first?.1 == 0 else { r.result = "focus_default_display_unverified"; return r }
    r.source = direct.isEmpty ? "displays" : "windows"; r.displayID = 0
    guard line.range(of: #"^mCurrentFocus=Window\{(?:com\.android\.systemui:)?[0-9a-f]+ u0 [^{}\r\n]+\}$"#, options: .regularExpression) != nil else {
        r.result = "focus_window_user_or_shape_unverified"; return r
    }
    let window = String(line.dropFirst("mCurrentFocus=".count))
    let blocks = windows.components(separatedBy: "Window #").filter { $0.components(separatedBy: .newlines).first?.contains(window) == true }
    guard blocks.count == 1 else { r.result = "focused_window_ambiguous"; return r }
    let expression = try! NSRegularExpression(pattern: #"\bmDisplayId=(\d+)\b"#)
    let block = blocks[0] as NSString
    let ids = expression.matches(in: blocks[0], range: NSRange(location: 0, length: block.length)).map { block.substring(with: $0.range(at: 1)) }
    guard !ids.isEmpty, ids.allSatisfy({ $0 == "0" }) else { r.result = "focused_window_display_mismatch"; return r }
    r.line = line; r.result = "focus_collected"; return r
}
func hierarchyDiagnostic(_ stdout: Data, stderr: Data, ok: Bool, parsed: PinXML? = nil) -> String {
    let combined = String(decoding: stdout + stderr, as: UTF8.self)
    if combined.contains("collector_blocked:") {
        for stage in ["stdout_guard", "device_config", "bridge_lookup", "bridge_accessor", "bridge_type", "root_query", "xml_walk", "field", "bounds", "limits", "output"] {
            if combined.contains("collector_blocked:" + stage + ":") { return "hierarchy_collector_" + stage + "_blocked" }
        }
        return "hierarchy_collector_blocked"
    }
    for (needle, category) in [("Permission denied", "hierarchy_permission_denied"), ("No such device or address", "hierarchy_fd_not_reopenable"), ("could not get idle state", "hierarchy_idle_timeout"), ("null root", "hierarchy_root_unavailable"), ("Exception", "hierarchy_exception")] {
        if combined.contains(needle) { return category }
    }
    guard ok else { return "hierarchy_query_failed_or_timeout" }
    guard !stdout.isEmpty else { return stderr.isEmpty ? "hierarchy_stdout_empty" : "hierarchy_stderr_without_xml" }
    guard combined.contains("<?xml"), combined.contains("</hierarchy>") else { return "hierarchy_no_xml" }
    guard let start = combined.range(of: "<?xml"), let end = combined.range(of: "</hierarchy>"), start.lowerBound < end.upperBound else { return "hierarchy_malformed_xml" }
    let xml = String(combined[start.lowerBound..<end.upperBound])
    guard !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else { return "hierarchy_unsafe_xml" }
    if parsed != nil { return "hierarchy_xml_parsed" }
    let parser = XMLParser(data: Data(xml.utf8)); parser.shouldResolveExternalEntities = false
    return parser.parse() ? "hierarchy_xml_parsed" : "hierarchy_malformed_xml"
}

struct SystemUIIdentity: Equatable { let pid: String; let uid: Int }
func systemUIIdentity(packageList: String, packageDump: String, process: String, pid: String) -> SystemUIIdentity? {
    guard Int(pid).map({ $0 > 0 }) == true else { return nil }
    let rows = packageList.components(separatedBy: .newlines).filter { $0.split(whereSeparator: { $0.isWhitespace }).first == "package:com.android.systemui" }
    guard rows.count == 1, rows[0].range(of: #"^package:com\.android\.systemui uid:\d+$"#, options: .regularExpression) != nil,
          let uid = Int(rows[0].split(separator: ":").last!), uid > 0, uid < 100000 else { return nil }
    let processRows = process.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
    guard processRows.count == 2, processRows[0] == ["UID", "PID", "NAME"], processRows[1] == [String(uid), pid, "com.android.systemui"] else { return nil }
    let lines = packageDump.components(separatedBy: .newlines)
    let headers = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).range(of: #"^Package \[com\.android\.systemui\] \([0-9a-f]+\):$"#, options: .regularExpression) != nil }
    guard headers.count == 1 else { return nil }
    let start = headers[0]; let depth = lines[start].prefix(while: { $0 == " " }).count
    let end = lines.indices.dropFirst(start + 1).first { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty && lines[$0].prefix(while: { $0 == " " }).count <= depth } ?? lines.count
    var fields: [String: String] = [:]
    for line in lines[(start + 1)..<end] where line.prefix(while: { $0 == " " }).count == depth + 2 {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2, ["appId", "userId", "flags", "pkgFlags", "privateFlags"].contains(parts[0]) {
            guard fields[parts[0]] == nil else { return nil }; fields[parts[0]] = parts[1]
        }
    }
    let ids = [fields["appId"], fields["userId"]].compactMap { $0 }
    guard !ids.isEmpty, ids.allSatisfy({ $0 == String(uid) }) else { return nil }
    let flags = [fields["flags"], fields["pkgFlags"]].compactMap { $0 }
    guard !flags.isEmpty, flags.allSatisfy({ $0.range(of: #"\bSYSTEM\b"#, options: .regularExpression) != nil }),
          fields["privateFlags"]?.range(of: #"\bPRIVILEGED\b"#, options: .regularExpression) != nil else { return nil }
    return SystemUIIdentity(pid: pid, uid: uid)
}

func wmAuthenticationArguments(_ serial: String) -> [String]? {
    guard validSerial(serial) else { return nil }
    return ["-s", serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/wm", "dismiss-keyguard"]
}
func wmAuthenticationCommandOK(stdout: Data, stderr: Data, ok: Bool) -> Bool {
    guard ok else { return false }
    let text = (String(decoding: stdout, as: UTF8.self) + String(decoding: stderr, as: UTF8.self)).lowercased()
    return !["permission denied", "permission denial", "permission exception", "securityexception", "security exception", "error", "exception", "failed"].contains(where: { text.contains($0) })
}
