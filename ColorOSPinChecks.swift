import Foundation

func runColorOSPinChecks(_ ck: (Bool) -> Void) {
    let window = "mCurrentFocus=Window{abc u0 NotificationShade}"
    func node(_ id: String, _ cls: String, bounds: String = "[0,0][800,1600]", focusable: Bool = false, clickable: Bool = false, desc: String = "", children: String = "") -> String {
        let resource = id.isEmpty ? "" : "com.android.systemui:id/" + id
        return "<node package=\"com.android.systemui\" resource-id=\"\(resource)\" class=\"\(cls)\" enabled=\"true\" password=\"false\" focused=\"false\" editable=\"false\" clickable=\"\(clickable)\" focusable=\"\(focusable)\" text=\"\" content-desc=\"\(desc)\" bounds=\"\(bounds)\">\(children)</node>"
    }
    let chain: [(String, String)] = [
        ("legacy_window_root", "android.widget.FrameLayout"), ("keyguard_bouncer_container", "android.widget.FrameLayout"),
        ("keyguard_security_container", "android.view.ViewGroup"), ("view_flipper", "android.widget.ViewFlipper"),
        ("oplusos_kgd_security_pin_six_view", "android.widget.RelativeLayout"), ("", "android.widget.LinearLayout")]
    let delete = node("", "android.widget.Button", bounds: "[500,1200][620,1320]", focusable: true, clickable: true, desc: "删除")
    let keys = (0...9).map { digit -> String in
        let cell = digit == 0 ? 10 : digit - 1
        let x = 100 + cell % 3 * 200, y = 600 + cell / 3 * 200
        return node("", "android.widget.Button", bounds: "[\(x),\(y)][\(x + 120),\(y + 120)]", focusable: true, clickable: true, desc: String(digit))
    }.joined()
    func fixture(_ count: Int, deleteVisible: Bool = false) -> String {
        let progress = node("", "android.view.View", bounds: "[0,300][800,330]", focusable: true, desc: "密码栏，已输入 \(count) 个值，共 6 个值")
        let field = node("colorSimpleLock", "android.view.View", bounds: "[0,300][800,400]", focusable: true, children: progress)
        let keyboard = node("pinColorNumericKeyboard", "android.view.View", bounds: "[100,600][700,1400]", focusable: true, children: keys + (deleteVisible ? delete : ""))
        return "<?xml version=\"1.0\"?><hierarchy>" + chain.reversed().reduce(field + keyboard) { node($1.0, $1.1, children: $0) } + "</hierarchy>"
    }
    let empty = fixture(0)
    let scrim = node("scrim_in_front", "android.view.View", clickable: true)
    let bouncerStart = "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/keyguard_bouncer_container\""
    let withScrim = empty.replacingOccurrences(of: bouncerStart, with: scrim + bouncerStart)
    ck(colorOSPinTarget(withScrim, window: window)?.count == 0)
    ck(colorOSPinTarget(empty.replacingOccurrences(of: bouncerStart, with: scrim + scrim + bouncerStart), window: window) == nil)
    for invalidScrim in [scrim.replacingOccurrences(of: "id/scrim_in_front", with: "id/unknown_scrim"), scrim.replacingOccurrences(of: "android.view.View", with: "android.widget.Button"), scrim.replacingOccurrences(of: "[0,0][800,1600]", with: "[0,0][800,1500]"), scrim.replacingOccurrences(of: "focusable=\"false\"", with: "focusable=\"true\"")] {
        ck(colorOSPinTarget(empty.replacingOccurrences(of: bouncerStart, with: invalidScrim + bouncerStart), window: window) == nil)
    }
    ck(colorOSPinTarget(empty.replacingOccurrences(of: "</hierarchy>", with: scrim + "</hierarchy>"), window: window) == nil)
    let target = colorOSPinTarget(empty, window: window)
    ck(target?.mode == .colorOSSix && target?.count == 0 && target?.keys.count == 10)
    for count in 0...6 { ck(colorOSEnteredCount("密码栏，已输入 \(count) 个值，共 6 个值") == count) }
    for count in 1...6 {
        ck(colorOSPinTarget(fixture(count), window: window)?.count == count)
        ck(colorOSPinTarget(fixture(count, deleteVisible: true), window: window)?.count == count)
    }
    ck(colorOSPinTarget(fixture(0, deleteVisible: true), window: window) == nil)
    for value in ["", "密码栏，已输入 0 个值，共 4 个值", "密码栏，已输入 7 个值，共 6 个值", "密码栏，已输入 00 个值，共 6 个值", "密码栏，已输入 -1 个值，共 6 个值", "密码栏，已输入 0 个值，共 6 个值\n", "prefix密码栏，已输入 0 个值，共 6 个值", "123456"] {
        ck(colorOSEnteredCount(value) == nil)
    }
    for (old, replacement) in [
        ("id/colorSimpleLock", "id/unknown_field"), ("id/pinColorNumericKeyboard", "id/unknown_keyboard"),
        ("id/oplusos_kgd_security_pin_six_view", "id/oplusos_kgd_security_pattern_view"),
        ("android.widget.Button", "android.view.View"), ("android.widget.RelativeLayout", "android.widget.LinearLayout"),
        ("package=\"com.android.systemui\"", "package=\"example.other\""),
        ("resource-id=\"com.android.systemui:id/", "resource-id=\"example.other:id/"),
        ("password=\"false\"", "password=\"true\""), ("focused=\"false\"", "focused=\"true\""),
        ("editable=\"false\"", "editable=\"true\""), ("enabled=\"true\"", "enabled=\"false\""),
        ("clickable=\"true\"", "clickable=\"false\""), ("focusable=\"true\"", "focusable=\"false\""),
        ("text=\"\"", "text=\"unexpected\""), ("content-desc=\"9\"", "content-desc=\"8\""),
        ("content-desc=\"9\"", "content-desc=\"other\""),
        ("[100,600][220,720]", "[300,600][420,720]"), ("[100,600][220,720]", "[0,600][90,720]"),
        ("[0,300][800,400]", "[0,300][800,1600]"), ("[0,300][800,330]", "[0,300][800,500]"),
        ("[0,0][800,1600]", "[1,0][800,1600]"), ("</hierarchy>", ""),
        ("<?xml version=\"1.0\"?>", "<?xml version=\"1.0\"?><!DOCTYPE hierarchy>")
    ] { ck(colorOSPinTarget(empty.replacingOccurrences(of: old, with: replacement), window: window) == nil) }
    ck(colorOSPinTarget(empty.replacingOccurrences(of: keys, with: keys + keys), window: window) == nil)
    ck(colorOSPinTarget(empty.replacingOccurrences(of: keys, with: node("unexpected_parent", "android.widget.FrameLayout", children: keys)), window: window) == nil)
    ck(colorOSPinTarget(empty.replacingOccurrences(of: "</hierarchy>", with: node("showPasswordButton", "android.widget.Button") + "</hierarchy>"), window: window) == nil)
    ck(colorOSPinTarget(empty.replacingOccurrences(of: "</hierarchy>", with: node("overlay", "android.widget.Button", bounds: "[100,600][220,720]", clickable: true) + "</hierarchy>"), window: window) == nil)
    ck(colorOSPinTarget(empty, window: window.replacingOccurrences(of: "u0", with: "u10")) == nil)
    ck(colorOSPinTarget(empty, window: window + "\n" + window) == nil)
    ck(colorOSCoverBounds(empty) == nil && colorOSInvitation(empty) == nil)

    var initial = Snapshot(); initial.serial = "fixture"; initial.user = 0; initial.online = true
    initial.secure = true; initial.state = .locked; initial.reason = "observed"; initial.awake = true
    initial.screenKnown = true; initial.userUnlocked = true; initial.bootComplete = true; initial.target = target
    var actions: [Int] = []; var finalObservations = 0
    let result = drivePIN(Data("012345".utf8), initial: initial, observe: { final in
        var current = initial
        if final { finalObservations += 1; current.state = .unlocked; current.target = nil }
        else { current.target = colorOSPinTarget(fixture(actions.count, deleteVisible: !actions.isEmpty), window: window) }
        return current
    }, send: { actions.append($0); return true })
    ck(result == .submitted && actions == [7, 8, 9, 10, 11, 12] && finalObservations == 1)
    ck(!actions.contains(66))
    for value in ["1234", "12345", "1234567"] {
        var reads = 0; var writes = 0
        ck(drivePIN(Data(value.utf8), initial: initial, observe: { _ in reads += 1; return initial }, send: { _ in writes += 1; return true }) == .refused)
        ck(reads == 0 && writes == 0)
    }
    var writes = 0
    ck(drivePIN(Data("012345".utf8), initial: initial, observe: { _ in initial }, send: { _ in writes += 1; return true }) == .partial)
    ck(writes == 1) // A missing increment never permits the next digit.
    writes = 0
    ck(drivePIN(Data("012345".utf8), initial: initial, observe: { _ in
        var current = initial; current.target = colorOSPinTarget(fixture(writes), window: window)
        if writes == 1 { current.serial = "other" }; return current
    }, send: { _ in writes += 1; return true }) == .partial)
    ck(writes == 1)
    var prefilled = initial; prefilled.target = colorOSPinTarget(fixture(1), window: window)
    var secrets = 0
    ck(attempt(prefilled, authorized: true, recheck: { prefilled }, read: { secrets += 1; return true }, submit: { .submitted }, confirm: { prefilled }).0 == "pin_field_not_empty")
    ck(secrets == 0)
}
