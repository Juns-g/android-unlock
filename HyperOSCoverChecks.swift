import Foundation

func runHyperOSCoverChecks(_ ck: (Bool) -> Void) {
    let sys = "com.android.systemui:id/", aod = "com.miui.aod:id/"
    func node(_ raw: String, _ cls: String = "android.widget.FrameLayout", package: String = "com.android.systemui", bounds: String = "[0,0][900,1800]", focused: Bool = false, clickable: Bool = false, focusable: Bool = false, children: String = "") -> String {
        "<node package=\"\(package)\" resource-id=\"\(raw)\" class=\"\(cls)\" bounds=\"\(bounds)\" focused=\"\(focused)\" clickable=\"\(clickable)\" focusable=\"\(focusable)\" enabled=\"true\" password=\"false\" editable=\"false\" text=\"\">\(children)</node>"
    }
    let left = node(aod + "shortcut_view_left", "android.widget.ImageView", package: "com.miui.aod", bounds: "[0,1500][240,1800]", focused: true, clickable: true, focusable: true)
    let leftLayout = node(aod + "shortcut_view_left_layout", package: "com.miui.aod", bounds: "[0,1500][240,1800]", children: left)
    let layout = node(aod + "keyguard_shortcut_layout", package: "com.miui.aod", bounds: "[0,1500][900,1800]", children: leftLayout)
    let wrapper = node("", package: "com.miui.aod", bounds: "[0,1500][900,1800]", children: layout)
    let shortcut = node(sys + "keyguard_shortcut_container", bounds: "[0,1500][900,1800]", children: wrapper)
    let bottom = node(sys + "keyguard_bottom_area", children: shortcut)
    let header = node(sys + "keyguard_header", "android.widget.RelativeLayout", bounds: "[0,0][900,100]")
    let keyguard = node(sys + "keyguard_root_view", "android.view.ViewGroup", children: header + bottom)
    let xml = "<?xml version=\"1.0\"?><hierarchy>" + node(sys + "legacy_window_root", children: keyguard) + "</hierarchy>"
    ck(hyperOSCoverVerified(xml))
    ck(parseHierarchy(xml)?.bad == true && !coverHierarchy(xml)) // The generic Space path stays closed.
    ck(hyperOSCoverVerified(xml.replacingOccurrences(of: "focused=\"true\"", with: "focused=\"false\"")))
    let indication = node(sys + "keyguard_indication_text_bottom", "android.widget.TextView", bounds: "[400,1650][500,1700]", focused: true, clickable: true, focusable: true)
    let indicationArea = node(sys + "keyguard_indication_area", "android.widget.LinearLayout", bounds: "[300,1550][600,1800]", children: indication)
    // Insert into the actual bottom-area ancestry after removing shortcut focus.
    let noFocusShortcut = shortcut.replacingOccurrences(of: "focused=\"true\"", with: "focused=\"false\"")
    let focusedIndicationXML = xml.replacingOccurrences(of: "focused=\"true\"", with: "focused=\"false\"").replacingOccurrences(of: noFocusShortcut, with: noFocusShortcut + indicationArea)
    ck(hyperOSCoverVerified(focusedIndicationXML))
    ck(!hyperOSCoverVerified(xml.replacingOccurrences(of: shortcut, with: shortcut + indicationArea)))
    ck(!hyperOSCoverVerified(focusedIndicationXML.replacingOccurrences(of: indication, with: indication + indication)))
    ck(!hyperOSCoverVerified(focusedIndicationXML.replacingOccurrences(of: "id/keyguard_indication_area", with: "id/unknown_area")))
    ck(!hyperOSCoverVerified(focusedIndicationXML.replacingOccurrences(of: "[400,1650][500,1700]", with: "[0,1500][100,1700]")))
    ck(!hyperOSCoverVerified(focusedIndicationXML.replacingOccurrences(of: "id/keyguard_indication_text_bottom\" class=\"android.widget.TextView", with: "id/keyguard_indication_text_bottom\" class=\"android.widget.EditText")))
    for (old, replacement) in [
        ("id/shortcut_view_left\"", "id/unknown_shortcut\""),
        ("id/keyguard_shortcut_layout", "id/unknown_layout"),
        ("id/keyguard_shortcut_container", "id/unknown_container"),
        ("id/keyguard_bottom_area", "id/unknown_bottom"),
        ("id/keyguard_root_view", "id/unknown_root"),
        ("id/keyguard_header", "id/unknown_header"),
        ("android.widget.ImageView", "android.widget.EditText"),
        ("android.widget.RelativeLayout", "android.widget.FrameLayout"),
        ("package=\"com.miui.aod\"", "package=\"example.other\""),
        ("package=\"com.android.systemui\"", "package=\"example.other\""),
        ("password=\"false\"", "password=\"true\""),
        ("editable=\"false\"", "editable=\"true\""),
        ("enabled=\"true\"", "enabled=\"false\""),
        ("clickable=\"true\"", "clickable=\"false\""),
        ("focusable=\"true\"", "focusable=\"false\""),
        ("[0,1500][240,1800]", "[0,1500][600,1800]"),
        ("[0,1500][240,1800]", "[10,1500][240,1800]"),
        ("[0,1500][900,1800]", "[0,200][900,1800]"),
        ("[0,0][900,100]", "[0,0][900,1700]"),
        ("[0,0][900,1800]", "[1,0][900,1800]"),
        ("</hierarchy>", ""),
        ("<?xml version=\"1.0\"?>", "<?xml version=\"1.0\"?><!DOCTYPE hierarchy>")
    ] { ck(!hyperOSCoverVerified(xml.replacingOccurrences(of: old, with: replacement))) }
    ck(!hyperOSCoverVerified(xml.replacingOccurrences(of: left, with: left + left)))
    ck(!hyperOSCoverVerified(xml.replacingOccurrences(of: left, with: node("unknown_parent", children: left))))
    ck(!hyperOSCoverVerified(xml.replacingOccurrences(of: "</hierarchy>", with: node(sys + "pinEntry") + "</hierarchy>")))
    ck(!hyperOSCoverVerified(xml.replacingOccurrences(of: "</hierarchy>", with: node(sys + "keyguard_bouncer_container") + "</hierarchy>")))
    ck(!hyperOSCoverVerified(xml.replacingOccurrences(of: "</hierarchy>", with: node(sys + "other_focused", focused: true) + "</hierarchy>")))
    ck(!hyperOSCoverVerified(""))
}
