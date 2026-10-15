import Foundation

// A focused lockscreen shortcut must never receive Space or a coordinate tap.
// This exact cover only permits the existing system authentication-page request.
private final class HyperOSCoverXML: NSObject, XMLParserDelegate {
    let sys = "com.android.systemui:id/"
    let aod = "com.miui.aod:id/"
    var stack: [String] = []
    var rectangles: [String: UIBounds] = [:]
    var invalid = false
    var focusedCount = 0
    var chain: [String] { [sys + "legacy_window_root", sys + "keyguard_root_view", sys + "keyguard_bottom_area", sys + "keyguard_shortcut_container", "", aod + "keyguard_shortcut_layout", aod + "shortcut_view_left_layout", aod + "shortcut_view_left"] }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard element == "node" else { return }
        let raw = a["resource-id"] ?? "", ancestors = stack
        stack.append(raw)
        if a["focused"] == "true" { focusedCount += 1 }
        guard ["com.android.systemui", "com.miui.aod", "miui.systemui.plugin"].contains(a["package"] ?? ""),
              a["password"] == "false", a["editable"] == "false",
              a["focused"] == "false" || raw == aod + "shortcut_view_left" || raw == sys + "keyguard_indication_text_bottom" else { invalid = true; return }
        if ["keyguard_bouncer_container", "keyguard_pin_view", "pinEntry", "passwordEntry", "lockPattern"].contains(raw.components(separatedBy: "/").last ?? "") {
            invalid = true; return
        }
        if raw == sys + "keyguard_indication_area" || raw == sys + "keyguard_indication_text_bottom" {
            let label = raw == sys + "keyguard_indication_text_bottom"
            let key = label ? "indicationText" : "indicationArea"
            let expectedAncestors = Array(chain.prefix(3)) + (label ? [sys + "keyguard_indication_area"] : [])
            guard ancestors == expectedAncestors, rectangles[key] == nil, a["package"] == "com.android.systemui",
                  a["class"] == (label ? "android.widget.TextView" : "android.widget.LinearLayout"),
                  a["enabled"] == "true", a["clickable"] == (label ? "true" : "false"),
                  a["focusable"] == (label ? "true" : "false"),
                  ["true", "false"].contains(a["focused"] ?? ""), let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
            rectangles[key] = rect; return
        }
        let index = chain.firstIndex(of: raw)
        let header = raw == sys + "keyguard_header"
        guard header || index != nil else { return }
        // Only the anonymous AOD wrapper at this exact position belongs to the proof.
        if raw.isEmpty && ancestors != Array(chain.prefix(4)) { return }
        let key = header ? "header" : "chain\(index!)"
        let shortcut = index == 7
        let expectedPackage = (index ?? 0) >= 4 ? "com.miui.aod" : "com.android.systemui"
        let cls = header ? "android.widget.RelativeLayout" : index == 1 ? "android.view.ViewGroup" : shortcut ? "android.widget.ImageView" : "android.widget.FrameLayout"
        guard ancestors == (header ? Array(chain.prefix(2)) : Array(chain.prefix(index!))),
              rectangles[key] == nil, a["package"] == expectedPackage, a["class"] == cls,
              a["enabled"] == "true", a["clickable"] == (shortcut ? "true" : "false"),
              a["focusable"] == (shortcut ? "true" : "false"),
              ["true", "false"].contains(a["focused"] ?? ""), let rect = uiBounds(a["bounds"] ?? "") else { invalid = true; return }
        rectangles[key] = rect
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "node" { stack.removeLast() }
    }
    var verified: Bool {
        // The OEM can expose both verified controls as focused at once; neither receives input here.
        guard !invalid, focusedCount <= 2, let root = rectangles["chain0"], root.x1 == 0, root.y1 == 0,
              rectangles["chain1"] == root, rectangles["chain2"] == root,
              let strip = rectangles["chain3"], rectangles["chain4"] == strip, rectangles["chain5"] == strip,
              strip.x1 == root.x1, strip.x2 == root.x2, strip.y2 == root.y2, strip.y1 > root.center.1,
              let left = rectangles["chain7"], rectangles["chain6"] == left,
              strip.contains(left), left.x1 == strip.x1, left.x2 < root.center.0, left.y1 == strip.y1, left.y2 == strip.y2,
              let header = rectangles["header"], root.contains(header), header.x1 == root.x1, header.x2 == root.x2,
              header.y1 == root.y1, header.y2 < root.center.1, !header.overlaps(strip) else { return false }
        if rectangles["indicationArea"] != nil || rectangles["indicationText"] != nil {
            guard let area = rectangles["indicationArea"], let label = rectangles["indicationText"],
                  strip.contains(area), area.contains(label), !label.overlaps(left), !label.overlaps(header) else { return false }
        }
        return true
    }
}

func hyperOSCoverVerified(_ xml: String) -> Bool {
    guard xml.utf8.count <= 1_048_576, !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY"),
          let start = xml.range(of: "<?xml"), let end = xml.range(of: "</hierarchy>"), start.lowerBound < end.upperBound else { return false }
    let delegate = HyperOSCoverXML()
    let parser = XMLParser(data: Data(xml[start.lowerBound..<end.upperBound].utf8))
    parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    return parser.parse() && delegate.verified
}
