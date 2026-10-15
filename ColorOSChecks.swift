import Foundation

func runColorOSChecks(_ ck: (Bool) -> Void) {
    func node(_ id: String, _ cls: String = "android.widget.FrameLayout", bounds: String = "[0,0][800,1600]", children: String = "") -> String {
        "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/\(id)\" class=\"\(cls)\" enabled=\"true\" password=\"false\" focused=\"false\" editable=\"false\" clickable=\"false\" text=\"\" bounds=\"\(bounds)\">\(children)</node>"
    }
    let panel = node("notification_panel", children:
        node("keyguard_slider_layout", "com.android.internal.widget.ViewPager") +
        node("keyguard_style_clock") + node("oplus_kgd_capsule_mask") +
        node("keyguard_bottom_area", bounds: "[20,100][780,1500]"))
    let xml = "<?xml version=\"1.0\"?><hierarchy>" + node("legacy_window_root", children:
        node("keyguard_root_view", "android.view.ViewGroup") + node("panel_view_pager", children: panel)) + "</hierarchy>"
    ck(colorOSCoverBounds(xml) == UIBounds(x1: 0, y1: 0, x2: 800, y2: 1600))
    for (old, replacement) in [
        ("id/keyguard_root_view", "id/unknown_root"),
        ("id/oplus_kgd_capsule_mask", "id/unknown_mask"),
        ("id/keyguard_slider_layout", "id/unknown_slider"),
        ("id/keyguard_style_clock", "id/unknown_clock"),
        ("id/keyguard_bottom_area", "id/unknown_bottom"),
        ("com.android.internal.widget.ViewPager", "android.view.View"),
        ("package=\"com.android.systemui\"", "package=\"example.other\""),
        ("resource-id=\"com.android.systemui:id/", "resource-id=\"example.other:id/"),
        ("password=\"false\"", "password=\"true\""),
        ("focused=\"false\"", "focused=\"true\""),
        ("editable=\"false\"", "editable=\"true\""),
        ("enabled=\"true\"", "enabled=\"false\""),
        ("clickable=\"false\"", "clickable=\"true\""),
        ("text=\"\"", "text=\"unexpected\""),
        ("[0,0][800,1600]", "[1,0][800,1600]"),
        ("[20,100][780,1500]", "[20,100][900,1700]"),
        ("</hierarchy>", ""),
        ("<?xml version=\"1.0\"?>", "<?xml version=\"1.0\"?><!DOCTYPE hierarchy>")
    ] { ck(colorOSCoverBounds(xml.replacingOccurrences(of: old, with: replacement)) == nil) }
    ck(colorOSCoverBounds(xml.replacingOccurrences(of: panel, with: panel + panel)) == nil)
    ck(colorOSCoverBounds(xml.replacingOccurrences(of: panel, with: node("unexpected_parent", children: panel))) == nil)
    ck(colorOSCoverBounds(xml.replacingOccurrences(of: "</hierarchy>", with: node("pinEntry").replacingOccurrences(of: "password=\"false\"", with: "password=\"true\"") + "</hierarchy>")) == nil)
    ck(colorOSCoverBounds("") == nil)
    func invitationNode(_ id: String, _ cls: String, children: String = "") -> String {
        let button = id == "showPasswordButton"
        return "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/\(id)\" class=\"\(cls)\" enabled=\"true\" password=\"false\" focused=\"false\" editable=\"false\" clickable=\"\(button)\" focusable=\"\(button)\" text=\"\" bounds=\"\(button ? "[200,800][600,900]" : "[0,0][800,1600]")\">\(children)</node>"
    }
    let chain: [(String, String)] = [
        ("legacy_window_root", "android.widget.FrameLayout"), ("keyguard_bouncer_container", "android.widget.FrameLayout"),
        ("keyguard_security_container", "android.view.ViewGroup"), ("view_flipper", "android.widget.ViewFlipper"),
        ("oplusos_kgd_security_pin_six_view", "android.widget.RelativeLayout"), ("kgd_security_switch_widget", "android.widget.FrameLayout"),
        ("showPasswordButton", "android.widget.Button")]
    let invitation = "<?xml version=\"1.0\"?><hierarchy>" + chain.reversed().reduce("") { invitationNode($1.0, $1.1, children: $0) } + "</hierarchy>"
    let scrim = node("scrim_in_front", "android.view.View").replacingOccurrences(of: "clickable=\"false\"", with: "clickable=\"true\"").replacingOccurrences(of: " text=", with: " focusable=\"false\" content-desc=\"\" text=")
    let bouncerStart = "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/keyguard_bouncer_container\""
    ck(colorOSInvitation(invitation.replacingOccurrences(of: bouncerStart, with: scrim + bouncerStart)) != nil)
    ck(colorOSInvitation(invitation.replacingOccurrences(of: bouncerStart, with: scrim + scrim + bouncerStart)) == nil)
    for invalidScrim in [scrim.replacingOccurrences(of: "id/scrim_in_front", with: "id/unknown_scrim"), scrim.replacingOccurrences(of: "android.view.View", with: "android.widget.Button"), scrim.replacingOccurrences(of: "[0,0][800,1600]", with: "[0,0][800,1500]"), scrim.replacingOccurrences(of: "focusable=\"false\"", with: "focusable=\"true\"")] {
        ck(colorOSInvitation(invitation.replacingOccurrences(of: bouncerStart, with: invalidScrim + bouncerStart)) == nil)
    }
    ck(colorOSInvitation(invitation.replacingOccurrences(of: "</hierarchy>", with: scrim + "</hierarchy>")) == nil)
    let revealed = colorOSInvitation(invitation)
    ck(revealed == ColorOSInvitation(bounds: UIBounds(x1: 0, y1: 0, x2: 800, y2: 1600), button: UIBounds(x1: 200, y1: 800, x2: 600, y2: 900)))
    ck(colorOSCoverBounds(invitation) == nil)
    ck(colorOSInvitation(xml) == nil)
    for (old, replacement) in [
        ("id/showPasswordButton", "id/unknown_button"), ("id/oplusos_kgd_security_pin_six_view", "id/unknown_pin_view"),
        ("id/kgd_security_switch_widget", "id/unknown_switch"), ("android.widget.Button", "android.widget.EditText"),
        ("package=\"com.android.systemui\"", "package=\"example.other\""), ("password=\"false\"", "password=\"true\""),
        ("focused=\"false\"", "focused=\"true\""), ("editable=\"false\"", "editable=\"true\""),
        ("clickable=\"true\"", "clickable=\"false\""), ("focusable=\"true\"", "focusable=\"false\""),
        ("enabled=\"true\"", "enabled=\"false\""), ("[200,800][600,900]", "[0,0][800,1600]"),
        ("[200,800][600,900]", "[200,800][900,1800]")
    ] { ck(colorOSInvitation(invitation.replacingOccurrences(of: old, with: replacement)) == nil) }
    let revealNode = invitationNode("showPasswordButton", "android.widget.Button")
    ck(colorOSInvitation(invitation.replacingOccurrences(of: revealNode, with: revealNode + revealNode)) == nil)
    ck(colorOSInvitation(invitation.replacingOccurrences(of: revealNode, with: invitationNode("unexpected_parent", "android.widget.FrameLayout", children: revealNode))) == nil)
    let overlay = node("overlay", "android.widget.Button", bounds: "[200,800][600,900]").replacingOccurrences(of: "clickable=\"false\"", with: "clickable=\"true\"")
    ck(colorOSInvitation(invitation.replacingOccurrences(of: "</hierarchy>", with: overlay + "</hierarchy>")) == nil)
    ck(colorOSInvitation(invitation.replacingOccurrences(of: "</hierarchy>", with: overlay.replacingOccurrences(of: "[200,800][600,900]", with: "[20,20][100,100]") + "</hierarchy>")) != nil)

    var base = Snapshot(); base.serial = "fixture"; base.user = 0; base.online = true; base.secure = true
    base.state = .locked; base.reason = "observed"; base.awake = true; base.screenKnown = true
    base.userUnlocked = true; base.bootComplete = true; base.coverIsColorOS = true
    base.coverWindow = "mCurrentFocus=Window{abc u0 NotificationShade}"; base.coverBounds = revealed!.bounds
    base.focusResult = "focus_identity_verified"; base.postUIStateChecked = true
    base.observedAt = 99; base.postUIVerifiedAt = 100
    var prompt = base; prompt.colorOSRevealButton = revealed!.button
    var requests = 0; var taps = 0; var observations = 0
    func prepare(_ first: Snapshot, next: Snapshot, requestOK: Bool = true, tapOK: Bool = true, time: Double = 100) -> Bool {
        var current = first
        return prepareColorOSPage(initial: first, current: &current, now: { time }, observe: { observations += 1; return next },
            request: { requests += 1; return requestOK }, tap: { rect in taps += 1; ck(rect == revealed!.button); return tapOK })
    }
    ck(prepare(base, next: prompt)); ck(requests == 1 && observations == 1 && taps == 1)
    ck(prepare(prompt, next: prompt)); ck(requests == 1 && observations == 1 && taps == 2)
    let oldTaps = taps
    var wrong = prompt; wrong.serial = "other"
    ck(!prepare(base, next: wrong)); ck(taps == oldTaps)
    wrong = prompt; wrong.user = 10
    ck(!prepare(base, next: wrong)); ck(taps == oldTaps)
    wrong = prompt; wrong.coverWindow = "mCurrentFocus=Window{def u0 NotificationShade}"
    ck(!prepare(base, next: wrong)); ck(taps == oldTaps)
    wrong = prompt; wrong.coverIsColorOS = false
    ck(!prepare(base, next: wrong)); ck(taps == oldTaps)
    wrong = prompt; wrong.focusResult = "focus_unverified"
    ck(!prepare(base, next: wrong)); ck(taps == oldTaps)
    wrong = prompt; wrong.postUIStateChecked = false
    ck(!prepare(base, next: wrong)); ck(taps == oldTaps)
    ck(!prepare(base, next: base)); ck(taps == oldTaps)
    ck(!prepare(base, next: prompt, requestOK: false)); ck(taps == oldTaps)
    let oldRequests = requests
    ck(!prepare(base, next: prompt, time: 103)); ck(requests == oldRequests && taps == oldTaps)
    ck(!prepare(prompt, next: prompt, tapOK: false)); ck(taps == oldTaps + 1 && requests == oldRequests)
}
