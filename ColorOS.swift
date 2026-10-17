import Foundation

// A ColorOS lockscreen cover is only a candidate for ordinary authentication presentation.
// The caller separately proves keyguard, SystemUI process/window ownership and display 0.
private final class ColorOSCoverXML: NSObject, XMLParserDelegate {
    var invalid = false
    var stack: [String] = []
    var rectangles: [String: UIBounds] = [:]
    let prefix = "com.android.systemui:id/"
    let paths: [String: [String]] = [
        "legacy_window_root": [],
        "keyguard_root_view": ["legacy_window_root"],
        "panel_view_pager": ["legacy_window_root"],
        "notification_panel": ["legacy_window_root", "panel_view_pager"],
        "keyguard_slider_layout": ["legacy_window_root", "panel_view_pager", "notification_panel"],
        "keyguard_style_clock": ["legacy_window_root", "panel_view_pager", "notification_panel"],
        "oplus_kgd_capsule_mask": ["legacy_window_root", "panel_view_pager", "notification_panel"],
        "keyguard_bottom_area": ["legacy_window_root", "panel_view_pager", "notification_panel"]
    ]
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard element == "node" else { return }
        let raw = a["resource-id"] ?? ""
        let id = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        let ancestors = stack; stack.append(id)
        // No password page, foreign application, editable field or ambiguous focus is a cover.
        guard a["package"] == "com.android.systemui", a["password"] == "false",
              a["focused"] == "false", a["editable"] == "false" else { invalid = true; return }
        guard let path = paths[id] else { return }
        let cls = id == "keyguard_root_view" ? "android.view.ViewGroup" :
            id == "keyguard_slider_layout" ? "com.android.internal.widget.ViewPager" : "android.widget.FrameLayout"
        guard raw == prefix + id, ancestors == path, rectangles[id] == nil,
              a["class"] == cls, a["enabled"] == "true", a["clickable"] == "false",
              a["text"] == "", let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
        rectangles[id] = rect
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "node" { stack.removeLast() }
    }
    var bounds: UIBounds? {
        guard !invalid, let root = rectangles["legacy_window_root"], root.x1 == 0, root.y1 == 0,
              paths.keys.allSatisfy({ rectangles[$0].map(root.contains) == true }),
              ["keyguard_root_view", "panel_view_pager", "notification_panel", "keyguard_slider_layout", "keyguard_style_clock", "oplus_kgd_capsule_mask"].allSatisfy({ rectangles[$0] == root }) else { return nil }
        return root
    }
}

func colorOSCoverBounds(_ xml: String) -> UIBounds? {
    guard xml.utf8.count <= 1_048_576, !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY"),
          let start = xml.range(of: "<?xml"), let end = xml.range(of: "</hierarchy>"), start.lowerBound < end.upperBound else { return nil }
    let delegate = ColorOSCoverXML()
    let parser = XMLParser(data: Data(xml[start.lowerBound..<end.upperBound].utf8))
    parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    return parser.parse() ? delegate.bounds : nil
}

struct ColorOSInvitation: Equatable {
    let bounds: UIBounds
    let button: UIBounds
}

private final class ColorOSInvitationXML: NSObject, XMLParserDelegate {
    var invalid = false
    var stack: [String] = []
    var rectangles: [String: UIBounds] = [:]
    var otherControls: [UIBounds] = []
    var backgroundSeen = false
    let prefix = "com.android.systemui:id/"
    let chain = ["legacy_window_root", "keyguard_bouncer_container", "keyguard_security_container", "view_flipper", "oplusos_kgd_security_pin_six_view", "kgd_security_switch_widget", "showPasswordButton"]
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard element == "node" else { return }
        let raw = a["resource-id"] ?? ""
        let id = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        let ancestors = stack; stack.append(id)
        guard a["package"] == "com.android.systemui", a["password"] == "false",
              a["focused"] == "false", a["editable"] == "false" else { invalid = true; return }
        if id == "scrim_in_front", a["clickable"] == "true" {
            // The observed dismiss-background precedes the bouncer, whose buttons received real preparation taps.
            guard !backgroundSeen, raw == prefix + id, ancestors == ["legacy_window_root"],
                  rectangles["keyguard_bouncer_container"] == nil, a["class"] == "android.view.View",
                  a["enabled"] == "true", a["focusable"] == "false", a["text"] == "", a["content-desc"] == "",
                  let rect = uiBounds(a["bounds"] ?? ""), rect == rectangles["legacy_window_root"] else { invalid = true; return }
            backgroundSeen = true; return
        }
        if a["clickable"] == "true", id != "showPasswordButton" {
            guard let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            otherControls.append(rect)
        }
        guard let index = chain.firstIndex(of: id) else { return }
        let cls: String
        switch id {
        case "keyguard_security_container": cls = "android.view.ViewGroup"
        case "view_flipper": cls = "android.widget.ViewFlipper"
        case "oplusos_kgd_security_pin_six_view": cls = "android.widget.RelativeLayout"
        case "showPasswordButton": cls = "android.widget.Button"
        default: cls = "android.widget.FrameLayout"
        }
        let button = id == "showPasswordButton"
        guard raw == prefix + id, ancestors == Array(chain.prefix(index)), rectangles[id] == nil,
              a["class"] == cls, a["enabled"] == "true", a["clickable"] == (button ? "true" : "false"),
              a["focusable"] == (button ? "true" : "false"),
              button || a["text"] == "", let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
        rectangles[id] = rect
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "node" { stack.removeLast() }
    }
    var result: ColorOSInvitation? {
        guard !invalid, let root = rectangles["legacy_window_root"], root.x1 == 0, root.y1 == 0,
              chain.dropLast().allSatisfy({ rectangles[$0] == root }),
              let button = rectangles["showPasswordButton"], button != root, root.contains(button),
              otherControls.allSatisfy({ !$0.overlaps(button) }) else { return nil }
        return ColorOSInvitation(bounds: root, button: button)
    }
}

func colorOSInvitation(_ xml: String) -> ColorOSInvitation? {
    guard xml.utf8.count <= 1_048_576, !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY"),
          let start = xml.range(of: "<?xml"), let end = xml.range(of: "</hierarchy>"), start.lowerBound < end.upperBound else { return nil }
    let delegate = ColorOSInvitationXML()
    let parser = XMLParser(data: Data(xml[start.lowerBound..<end.upperBound].utf8))
    parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    return parser.parse() ? delegate.result : nil
}

// ColorOS may insert a biometric invitation between the cover and the six-digit keypad.
// Permit one system request and one verified nonsecret reveal-button tap; never loop or enter a PIN here.
func prepareColorOSPage(initial: Snapshot, current: inout Snapshot, now: () -> Double,
                        observe: () -> Snapshot, request: () -> Bool, tap: (UIBounds) -> Bool) -> Bool {
    guard current.coverIsColorOS, immediateCoverObservation(initial, current, now: now()),
          let window = current.coverWindow else { return false }
    if current.colorOSRevealButton == nil {
        guard request() else { return false }
        current = observe()
        if decision(current) == "ready" {
            return consistent(initial, current) && current.target?.window == window
        }
    }
    guard current.coverIsColorOS, current.coverWindow == window,
          immediateCoverObservation(initial, current, now: now()),
          let rect = current.colorOSRevealButton, current.coverBounds?.contains(rect) == true else { return false }
    return tap(rect)
}

func colorOSEnteredCount(_ description: String) -> Int? {
    // Exact localized accessibility count, not text from the password or keyboard.
    let expression = try! NSRegularExpression(pattern: #"^密码栏，已输入 ([0-6]) 个值，共 6 个值$"#)
    let text = description as NSString
    guard let match = expression.firstMatch(in: description, range: NSRange(location: 0, length: text.length)),
          match.range.length == text.length else { return nil }
    return Int(text.substring(with: match.range(at: 1)))
}

private final class ColorOSPinXML: NSObject, XMLParserDelegate {
    var invalid = false
    var stack: [String] = []
    var rectangles: [String: UIBounds] = [:]
    var keys: [Int: UIBounds] = [:]
    var delete: UIBounds? = nil
    var count: Int? = nil
    var progressBounds: UIBounds? = nil
    var containers = 0
    var otherControls: [UIBounds] = []
    var backgroundSeen = false
    let prefix = "com.android.systemui:id/"
    let chain = ["legacy_window_root", "keyguard_bouncer_container", "keyguard_security_container", "view_flipper", "oplusos_kgd_security_pin_six_view"]
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard element == "node" else { return }
        let raw = a["resource-id"] ?? ""
        let id = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        let ancestors = stack; stack.append(id)
        guard a["package"] == "com.android.systemui", a["password"] == "false",
              a["focused"] == "false", a["editable"] == "false" else { invalid = true; return }
        if id == "scrim_in_front", a["clickable"] == "true" {
            guard !backgroundSeen, raw == prefix + id, ancestors == ["legacy_window_root"],
                  rectangles["keyguard_bouncer_container"] == nil, a["class"] == "android.view.View",
                  a["enabled"] == "true", a["focusable"] == "false", a["text"] == "", a["content-desc"] == "",
                  let rect = uiBounds(a["bounds"] ?? ""), rect == rectangles["legacy_window_root"] else { invalid = true; return }
            backgroundSeen = true; return
        }
        if a["clickable"] == "true", ancestors != chain + ["", "pinColorNumericKeyboard"] {
            guard let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            otherControls.append(rect)
        }
        if id == "showPasswordButton" { invalid = true; return }
        if let index = chain.firstIndex(of: id) {
            let cls: String
            switch id {
            case "keyguard_security_container": cls = "android.view.ViewGroup"
            case "view_flipper": cls = "android.widget.ViewFlipper"
            case "oplusos_kgd_security_pin_six_view": cls = "android.widget.RelativeLayout"
            default: cls = "android.widget.FrameLayout"
            }
            guard raw == prefix + id, ancestors == Array(chain.prefix(index)), rectangles[id] == nil,
                  a["class"] == cls, a["enabled"] == "true", a["clickable"] == "false", a["focusable"] == "false",
                  a["text"] == "", let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            rectangles[id] = rect; return
        }
        if raw.isEmpty, ancestors == chain {
            guard a["class"] == "android.widget.LinearLayout", a["enabled"] == "true", a["clickable"] == "false",
                  a["focusable"] == "false", a["text"] == "", let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            containers += 1; rectangles["container"] = rect; return
        }
        let parent = chain + [""]
        if ["colorSimpleLock", "pinColorNumericKeyboard"].contains(id) {
            guard raw == prefix + id, ancestors == parent, rectangles[id] == nil,
                  a["class"] == "android.view.View", a["enabled"] == "true", a["clickable"] == "false", a["focusable"] == "true",
                  a["text"] == "", a["content-desc"] == "", let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            rectangles[id] = rect; return
        }
        if ancestors == parent + ["colorSimpleLock"] {
            guard raw.isEmpty, count == nil, a["class"] == "android.view.View", a["enabled"] == "true",
                  a["clickable"] == "false", a["focusable"] == "true", a["text"] == "",
                  let entered = colorOSEnteredCount(a["content-desc"] ?? ""), let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            count = entered; progressBounds = rect; return
        }
        if ancestors == parent + ["pinColorNumericKeyboard"] {
            guard raw.isEmpty, a["class"] == "android.widget.Button", a["enabled"] == "true",
                  a["clickable"] == "true", a["focusable"] == "true", a["text"] == "",
                  let label = a["content-desc"], let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            if label.count == 1, let digit = Int(label), (0...9).contains(digit), label == String(digit) {
                guard keys[digit] == nil else { invalid = true; return }; keys[digit] = rect
            } else if label == "删除", delete == nil { delete = rect }
            else { invalid = true }
        } else if ancestors.contains("colorSimpleLock") || ancestors.contains("pinColorNumericKeyboard") {
            invalid = true
        }
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "node" { stack.removeLast() }
    }
    func target(window: String) -> PinTarget? {
        guard !invalid, containers == 1, let root = rectangles["legacy_window_root"], root.x1 == 0, root.y1 == 0,
              chain.allSatisfy({ rectangles[$0] == root }), rectangles["container"] == root,
              let field = rectangles["colorSimpleLock"], let progress = progressBounds, let count,
              let keyboard = rectangles["pinColorNumericKeyboard"], root.contains(field), field.contains(progress),
              root.contains(keyboard), !field.overlaps(keyboard), keys.count == 10,
              (0...9).allSatisfy({ keys[$0].map(keyboard.contains) == true }) else { return nil }
        let controls = Array(keys.values) + (delete.map { [$0] } ?? [])
        guard otherControls.allSatisfy({ other in !other.overlaps(field) && controls.allSatisfy({ !other.overlaps($0) }) }) else { return nil }
        for i in controls.indices { for j in 0..<i { guard !controls[i].overlaps(controls[j]) else { return nil } } }
        if let delete { guard keyboard.contains(delete), count > 0 else { return nil } }
        return PinTarget(window: window, field: "[\(field.x1),\(field.y1)][\(field.x2),\(field.y2)]", count: count, mode: .colorOSSix, keys: keys)
    }
}

func colorOSPinTarget(_ xml: String, window: String) -> PinTarget? {
    guard window.range(of: #"^mCurrentFocus=Window\{(?:com\.android\.systemui:)?[0-9a-f]+ u0 [^{}\r\n]+\}$"#, options: .regularExpression) != nil,
          xml.utf8.count <= 1_048_576, !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY"),
          let start = xml.range(of: "<?xml"), let end = xml.range(of: "</hierarchy>"), start.lowerBound < end.upperBound else { return nil }
    let delegate = ColorOSPinXML()
    let parser = XMLParser(data: Data(xml[start.lowerBound..<end.upperBound].utf8))
    parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    return parser.parse() ? delegate.target(window: window) : nil
}
