import Foundation
@main struct Checks {
 static func main() {
    var n = 0
    func ck(_ b: Bool, line: UInt = #line) { precondition(b, "check \(n + 1) failed at Checks.swift:\(line)"); n += 1 }
    runColorOSChecks { ck($0) }
    runColorOSPinChecks { ck($0) }
    runHyperOSCoverChecks { ck($0) }
    #if HYPEROS_STANDALONE
    ck(identity == "page.juns.AndroidUnlockHyperOSHelper")
    ck(stablePath.hasSuffix("/Applications/AndroidUnlockHyperOSHelper.app/Contents/MacOS/android-unlock"))
    #else
    ck(identity == "page.juns.AndroidUnlockHelper")
    ck(stablePath.hasSuffix("/Applications/AndroidUnlockHelper.app/Contents/MacOS/android-unlock"))
    #endif
    ck(service == "page.juns.android-unlock.pin.v1")
    let fixture = """
      KeyguardServiceDelegate
        showing=true
        inputRestricted=true
        occluded=false
        secure=true
        bootCompleted=true
        currentUser=0
        screenState=SCREEN_STATE_ON
        interactiveState=INTERACTIVE_STATE_AWAKE
    """
    let focus = "mCurrentFocus=Window{abc u0 NotificationShade}"
    let xml = "<?xml version=\"1.0\"?><hierarchy><node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/pinEntry\" class=\"android.widget.EditText\" password=\"true\" enabled=\"true\" focusable=\"true\" focused=\"true\" text=\"\" bounds=\"[0,1][2,3]\"/></hierarchy>"
    var s = parseState(serial: "fixture", userText: "0", policyText: fixture); s.userUnlocked = true; s.target = pinTarget(xml: xml, windowText: focus)
    ck(s.target != nil); ck(decision(s) == "ready")
    ck(pinTarget(xml: xml.replacingOccurrences(of: "password=\"true\"", with: "password=\"false\""), windowText: focus) == nil)
    ck(pinTarget(xml: xml, windowText: focus.replacingOccurrences(of: "u0", with: "u10")) == nil)
    ck(pinTarget(xml: xml.replacingOccurrences(of: "com.android.systemui", with: "arbitrary.app"), windowText: focus) == nil)
    for bad in [fixture + "\n    showing=false", fixture.replacingOccurrences(of: "inputRestricted=true", with: "inputRestricted=false"), fixture.replacingOccurrences(of: "SCREEN_STATE_ON", with: "SCREEN_STATE_OFF"), ""] {
        ck(parseState(serial: "fixture", userText: "0", policyText: bad).reason != "observed")
    }
    ck(deviceDecision(devices("List of devices attached\n"), serial: "x") == "device_missing")
    ck(deviceDecision(devices("List of devices attached\na unauthorized\n"), serial: "a") == "device_not_authorized_online")
    ck(deviceDecision(devices("List of devices attached\na device\nb device\n"), serial: "b") == "online")
    ck(deviceDecision(devices("List of devices attached\na device\nb device\n"), serial: "c") == "device_missing")
    ck(devices("List of devices attached\na device\na device\n") == nil)
    let spaced = "List of devices attached\n10.0.0.8:5555 device product:example\nadb-EXAMPLE (2)._adb-tls-connect._tcp device product:example\n"
    ck(deviceDecision(devices(spaced), serial: "10.0.0.8:5555") == "online")
    ck(deviceDecision(devices(spaced), serial: "adb-EXAMPLE (2)._adb-tls-connect._tcp") == "online")
    ck(devices("List of devices attached\na;sh device\n") == nil)
    ck(devices("List of devices attached\n device\n") == nil)
    ck(!validSerial("a;sh")); ck(!validSerial(" serial")); ck(!validSerial("serial ")); ck(!validPIN(Data("12x4".utf8))); ck(validPIN(Data("0123".utf8)))
    var unlocked = s; unlocked.state = .unlocked; unlocked.target = nil
    var reads = 0; var inputs = 0
    func run(_ initial: Snapshot, auth: Bool = true, fresh: Snapshot? = nil, result: InputResult = .submitted, after: Snapshot? = nil) -> (String, Bool) {
        attempt(initial, authorized: auth, recheck: { fresh ?? initial }, read: { reads += 1; return true }, submit: { inputs += 1; return result }, confirm: { after ?? unlocked })
    }
    ck(run(s).0 == "unlocked_confirmed"); ck(reads == 1 && inputs == 1)
    ck(run(s, after: s).0 == "confirmation_failed_no_retry")
    ck(run(s, result: .partial).0 == "partial_input_aborted_no_retry")
    var changed = s; changed.target = PinTarget(window: "changed", field: "x", count: 0)
    let prior = reads; ck(run(s, fresh: changed).0 == "state_changed_before_secret"); ck(reads == prior)
    changed = s; changed.user = 10; ck(run(s, fresh: changed).0 == "state_changed_before_secret")
    changed = s; changed.serial = "other"; ck(run(s, fresh: changed).0 == "state_changed_before_secret")
    let priorInput = inputs; ck(run(s, auth: false).0 == "authorization_required"); ck(run(unlocked).0 == "already_unlocked"); ck(inputs == priorInput && reads == prior)
    ck(setup(unlocked) == "install_at_stable_path_first")
    ck(verifiedWindow("Window #0 Window{abc u0 NotificationShade}:\n mOwnerUid=1000\n mSession=Session{def 123:1000}\n mAttrs={ty=NOTIFICATION_SHADE}", target: s.target!, pid: "123", uid: 1000))
    let darkText = fixture.replacingOccurrences(of: "SCREEN_STATE_ON", with: "SCREEN_STATE_OFF").replacingOccurrences(of: "INTERACTIVE_STATE_AWAKE", with: "INTERACTIVE_STATE_SLEEP")
    var dark = parseState(serial: "fixture", userText: "0", policyText: darkText); dark.userUnlocked = true
    ck(dark.reason == "observed" && dark.state == .locked && !dark.awake && dark.screenKnown)
    ck(decision(dark) == "preparation_needed_wake")
    var cover = s; cover.target = nil; cover.coverWindow = focus
    ck(decision(cover) == "preparation_needed_pin_page")
    let coverXML = "<?xml version=\"1.0\"?><hierarchy><node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/keyguard_status_view\"/></hierarchy>"
    ck(coverHierarchy(coverXML)); ck(!coverHierarchy(xml))
    let unsafeCoverXML = coverXML.replacingOccurrences(of: "</hierarchy>", with: "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/passwordEntry\" class=\"android.widget.EditText\" focused=\"true\" password=\"true\" enabled=\"true\" text=\"\"/></hierarchy>")
    ck(!coverHierarchy(unsafeCoverXML))
    var wakes = 0; var presents = 0
    func prep(_ initial: Snapshot, auth: Bool = true, fresh: Snapshot? = nil, woke: Snapshot? = nil, wakeOK: Bool = true, presentOK: Bool = true, presented: Snapshot? = nil) -> Preparation {
        var observations = 0
        return prepare(initial, authorized: auth, observe: {
            observations += 1
            return fresh ?? (observations == 1 ? initial : cover)
        }, wake: { wakes += 1; return wakeOK }, afterWake: { woke ?? cover }, present: { presents += 1; return presentOK }, afterPresent: { presented ?? s })
    }
    let full = prep(dark)
    ck(full.result == "ready" && full.wakeAttempted && full.presentationAttempted)
    ck(run(full.snapshot).0 == "unlocked_confirmed")
    ck(wakes == 1 && presents == 1)
    let oldWakes = wakes
    ck(prep(s).result == "ready"); ck(wakes == oldWakes)
    ck(prep(unlocked).result == "already_unlocked"); ck(wakes == oldWakes)
    let oldSecrets = reads
    // Read-only planning calls decision only, never any preparation/credential closure.
    for item in [dark, cover, s] { _ = decision(item) }
    ck(wakes == oldWakes && reads == oldSecrets)
    ck(prep(dark, wakeOK: false).result == "wake_command_failed_no_retry")
    ck(prep(dark, woke: dark).result == "wake_unconfirmed_no_retry")
    ck(prep(cover, presentOK: false).result == "presentation_command_failed_no_retry")
    ck(prep(cover, presented: cover).result == "pin_page_unconfirmed_no_retry")
    var unsafe = cover; unsafe.coverWindow = nil
    ck(!prep(unsafe).attempted)
    var wrong = dark; wrong.serial = "wrong"
    ck(!prep(dark, fresh: wrong).attempted)
    wrong = dark; wrong.user = 10
    ck(!prep(dark, fresh: wrong).attempted)
    let beforeBlocked = wakes
    for reason in ["device_missing", "device_not_authorized_online", "keyguard_ambiguous"] {
        var blocked = dark; blocked.reason = reason; ck(!prep(blocked).attempted)
    }
    var boot = dark; boot.userUnlocked = false; ck(!prep(boot).attempted)
    ck(!prep(dark, auth: false).attempted); ck(wakes == beforeBlocked && reads == oldSecrets)
    ck(prep(cover, fresh: unsafe).result == "secure_empty_pin_target_unverified")
    var observations = 0
    let changedFocus = prepare(cover, authorized: true, observe: { observations += 1; return observations == 1 ? cover : unsafe }, wake: { false }, afterWake: { dark }, present: { preconditionFailure("unsafe presentation") }, afterPresent: { s })
    ck(changedFocus.result == "presentation_focus_changed" && !changedFocus.presentationAttempted)
    var transition = parseState(serial: "fixture", userText: "0", policyText: fixture.replacingOccurrences(of: "SCREEN_STATE_ON", with: "SCREEN_STATE_TURNING_ON").replacingOccurrences(of: "INTERACTIVE_STATE_AWAKE", with: "INTERACTIVE_STATE_WAKING"))
    transition.userUnlocked = true
    ck(transition.reason == "screen_state_unknown" && transition.state == .locked && !transition.awake)
    ck(canSettleWake(dark, transition)); ck(decision(transition) != "ready")
    var invalidTransition = transition; invalidTransition.user = 10; ck(!canSettleWake(dark, invalidTransition))
    invalidTransition = transition; invalidTransition.serial = "other"; ck(!canSettleWake(dark, invalidTransition))
    invalidTransition = transition; invalidTransition.state = .unknown; ck(!canSettleWake(dark, invalidTransition))
    invalidTransition = transition; invalidTransition.userUnlocked = false; ck(!canSettleWake(dark, invalidTransition))
    invalidTransition = transition; invalidTransition.online = false; ck(!canSettleWake(dark, invalidTransition))
    let liveLocked = """
        KeyguardServiceDelegate
          showing=true
          inputRestricted=false
          occluded=false
          secure=true
          currentUser=-10000
          bootCompleted=true
          screenState=SCREEN_STATE_OFF
          interactiveState=INTERACTIVE_STATE_SLEEP
          KeyguardStateMonitor
            mIsShowing=true
            mInputRestricted=true
            mCurrentUserId=0
    """
    let liveUnlocked = liveLocked.replacingOccurrences(of: "showing=true", with: "showing=false")
        .replacingOccurrences(of: "mIsShowing=true", with: "mIsShowing=false")
        .replacingOccurrences(of: "mInputRestricted=true", with: "mInputRestricted=false")
        .replacingOccurrences(of: "SCREEN_STATE_OFF", with: "SCREEN_STATE_ON")
        .replacingOccurrences(of: "INTERACTIVE_STATE_SLEEP", with: "INTERACTIVE_STATE_AWAKE")
    let liveDark = parseState(serial: "fixture", userText: "0", policyText: liveLocked)
    ck(liveDark.state == .locked && liveDark.reason == "observed" && liveDark.screenKnown && !liveDark.awake)
    let liveOn = parseState(serial: "fixture", userText: "0", policyText: liveUnlocked)
    ck(liveOn.state == .unlocked && liveOn.reason == "observed" && liveOn.awake)
    ck(parseState(serial: "fixture", userText: "10", policyText: liveLocked).state == .unknown)
    for bad in [
        liveLocked.replacingOccurrences(of: "mCurrentUserId=0", with: "mCurrentUserId=10"),
        liveLocked.replacingOccurrences(of: "mCurrentUserId=0", with: ""),
        liveLocked.replacingOccurrences(of: "mIsShowing=true", with: ""),
        liveLocked.replacingOccurrences(of: "mInputRestricted=true", with: ""),
        liveLocked.replacingOccurrences(of: "mCurrentUserId=0", with: "mCurrentUserId=0\n        mCurrentUserId=0"),
        liveLocked.replacingOccurrences(of: "mInputRestricted=true", with: "mInputRestricted=false"),
        liveLocked.replacingOccurrences(of: "currentUser=-10000", with: "currentUser=10"),
        liveLocked.replacingOccurrences(of: "currentUser=-10000", with: "currentUser=-2"),
        liveLocked + "\n      KeyguardStateMonitor\n        mCurrentUserId=0",
        liveLocked.replacingOccurrences(of: "      KeyguardStateMonitor", with: "KeyguardStateMonitor"),
        liveLocked.replacingOccurrences(of: "        mCurrentUserId=0", with: "          mCurrentUserId=0"),
        fixture.replacingOccurrences(of: "currentUser=0", with: "currentUser=-10000")
    ] { ck(parseState(serial: "fixture", userText: "0", policyText: bad).state == .unknown) }
    ck(parseState(serial: "fixture", userText: "0", policyText: liveLocked.replacingOccurrences(of: "currentUser=-10000", with: "currentUser=0")).state == .locked)
    let windowDump = "Window #0 Window{abc u0 NotificationShade}:\n  mDisplayId=0\n  mOwnerUid=1000\n  mSession=Session{def 123:1000}\n mAttrs={ty=NOTIFICATION_SHADE}"
    let displayDump = "  Display: mDisplayId=0\n  mCurrentFocus=Window{abc u0 NotificationShade}"
    let collected = focusObservation(windows: windowDump, displays: displayDump)
    ck(collected.line == focus && collected.source == "displays" && collected.displayID == 0)
    ck(verifiedWindow(windowDump, target: s.target!, pid: "123", uid: 1000))
    ck(!verifiedWindow(windowDump.replacingOccurrences(of: "mOwnerUid=1000", with: "mOwnerUid=10001"), target: s.target!, pid: "123", uid: 1000))
    ck(!verifiedWindow(windowDump, target: s.target!, pid: "999", uid: 1000))
    ck(focusObservation(windows: windowDump, displays: displayDump.replacingOccurrences(of: "mDisplayId=0", with: "mDisplayId=1")).line == nil)
    ck(focusObservation(windows: windowDump.replacingOccurrences(of: "mDisplayId=0", with: "mDisplayId=1"), displays: displayDump).line == nil)
    ck(focusObservation(windows: windowDump, displays: displayDump + "\n  Display: mDisplayId=1\n  mCurrentFocus=Window{abc u0 NotificationShade}").line == nil)
    ck(focusObservation(windows: windowDump + "\n" + focus.replacingOccurrences(of: "abc", with: "bad"), displays: displayDump).result == "focus_sources_conflict")
    ck(focusObservation(windows: windowDump, displays: displayDump.replacingOccurrences(of: "u0 NotificationShade", with: "u10 NotificationShade")).line == nil)
    ck(focusObservation(windows: windowDump, displays: displayDump.replacingOccurrences(of: "NotificationShade", with: "FIXTURE_PRIVATE_APP")).result == "focused_window_ambiguous")
    let colorOSDisplay = "WINDOW MANAGER DISPLAY CONTENTS (dumpsys window displays)\n  Display: mDisplayId=0 (organized)\n    init=1440x3168 cur=1440x3168 app=1440x3069 rng=0x0-0x0\n"
    for density in ["mIsDensityForced=false", "mIsDensityForced=true"] {
        let observed = focusObservation(windows: windowDump, displays: colorOSDisplay + density + "\n  " + focus)
        ck(observed.line == focus && observed.source == "displays" && observed.displayID == 0 && observed.result == "focus_collected")
        ck(focusObservation(windows: windowDump, displays: density + "\n  " + focus).result == "focus_display_unscoped")
    }
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=true\nmIsDensityForced=false\n  " + focus).result == "focus_collected")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=false \n  " + focus).result == "focus_collected")
    ck(focusObservation(windows: windowDump, displays: "mIsDensityForced=false\n" + displayDump).result == "focus_collected")
    ck(focusObservation(windows: windowDump, displays: "  Display: mDisplayId=0\n  mIsDensityForced=false\n  " + focus).result == "focus_collected")
    ck(focusObservation(windows: windowDump, displays: "  Display: mDisplayId=0\n    mIsDensityForced=true\n  " + focus).result == "focus_collected")
    let agreed = focusObservation(windows: windowDump + "\n" + focus, displays: colorOSDisplay + "mIsDensityForced=true\n  " + focus)
    ck(agreed.line == focus && agreed.source == "windows" && agreed.displayID == 0 && agreed.result == "focus_collected")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=false").result == "focus_missing")
    for density in ["mIsDensityForced=false extra", "mIsDensityForced=false mBaseDisplayDensity=0", "mIsDensityForced=", "mIsDensityForced=False", "mIsDensityForced=1", "mIsDensityForced=truefalse", "mIsDensityForced=false,true", "not mIsDensityForced=false", "mIsDensityForced=false\textra"] {
        ck(focusObservation(windows: windowDump, displays: colorOSDisplay + density + "\n  " + focus).result == "focus_display_unscoped")
    }
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "ARBITRARY_SECTION\n  " + focus).result == "focus_display_unscoped")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=false\nARBITRARY_SECTION\n  " + focus).result == "focus_display_unscoped")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "ARBITRARY_SECTION\nmIsDensityForced=true\n  " + focus).result == "focus_display_unscoped")
    let displayOne = colorOSDisplay.replacingOccurrences(of: "mDisplayId=0", with: "mDisplayId=1")
    ck(focusObservation(windows: windowDump, displays: displayOne + "mIsDensityForced=true\n  " + focus).result == "focus_default_display_unverified")
    ck(focusObservation(windows: windowDump, displays: displayOne + "mIsDensityForced=false\n  " + focus).result == "focus_default_display_unverified")
    ck(focusObservation(windows: windowDump + "\n" + focus.replacingOccurrences(of: "abc", with: "bad"), displays: colorOSDisplay + "mIsDensityForced=false\n  " + focus).result == "focus_sources_conflict")
    ck(focusObservation(windows: windowDump + "\n" + focus + "\n" + focus.replacingOccurrences(of: "abc", with: "def"), displays: colorOSDisplay + "mIsDensityForced=false\n  " + focus).result == "focus_ambiguous")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=false\n  " + focus + "\n  " + focus.replacingOccurrences(of: "abc", with: "def")).result == "focus_ambiguous")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=false\n  " + focus + "\n" + displayOne + "mIsDensityForced=true\n  " + focus).result == "focus_ambiguous")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=false\n  " + focus.replacingOccurrences(of: "NotificationShade", with: "FIXTURE_PRIVATE_APP")).result == "focused_window_ambiguous")
    ck(focusObservation(windows: windowDump, displays: colorOSDisplay + "mIsDensityForced=true\n  " + focus.replacingOccurrences(of: "u0", with: "u10")).result == "focus_window_user_or_shape_unverified")
    ck(focusObservation(windows: windowDump.replacingOccurrences(of: "mDisplayId=0", with: "mDisplayId=1"), displays: colorOSDisplay + "mIsDensityForced=false\n  " + focus).result == "focused_window_display_mismatch")
    let namespacedColorOS = focus.replacingOccurrences(of: "Window{abc", with: "Window{com.android.systemui:ab12cd3")
    ck(focusObservation(windows: windowDump.replacingOccurrences(of: "Window{abc", with: "Window{com.android.systemui:ab12cd3"), displays: colorOSDisplay + "mIsDensityForced=false\n  " + namespacedColorOS).line == namespacedColorOS)
    ck(focusObservation(windows: windowDump.replacingOccurrences(of: "Window{abc", with: "Window{arbitrary.app:ab12cd3"), displays: colorOSDisplay + "mIsDensityForced=false\n  " + focus.replacingOccurrences(of: "Window{abc", with: "Window{arbitrary.app:ab12cd3")).result == "focus_window_user_or_shape_unverified")
    ck(hierarchyDiagnostic(Data(), stderr: Data(), ok: true) == "hierarchy_stdout_empty")
    ck(hierarchyDiagnostic(Data(), stderr: Data("No such device or address".utf8), ok: true) == "hierarchy_fd_not_reopenable")
    ck(hierarchyDiagnostic(Data("FIXTURE_PRIVATE_TEXT".utf8), stderr: Data(), ok: true) == "hierarchy_no_xml")
    ck(hierarchyDiagnostic(Data(xml.utf8), stderr: Data(), ok: true) == "hierarchy_xml_parsed")
    let packageList = "package:com.android.systemui uid:10123\n"
    let packageDump = "  Package [com.android.systemui] (abc):\n    appId=10123\n    flags=[ SYSTEM HAS_CODE ]\n    pkgFlags=[ SYSTEM HAS_CODE ]\n    privateFlags=[ PRIVILEGED ]\n"
    let processRows = "UID PID NAME\n10123 4321 com.android.systemui\n"
    let trusted = systemUIIdentity(packageList: packageList, packageDump: packageDump, process: processRows, pid: "4321")
    ck(trusted == SystemUIIdentity(pid: "4321", uid: 10123))
    ck(systemUIIdentity(packageList: packageList, packageDump: packageDump.replacingOccurrences(of: "PRIVILEGED", with: "NOT_PRIVILEGED"), process: processRows, pid: "4321") == nil)
    ck(systemUIIdentity(packageList: packageList, packageDump: packageDump.replacingOccurrences(of: "SYSTEM", with: "NOT_SYSTEM"), process: processRows, pid: "4321") == nil)
    ck(systemUIIdentity(packageList: packageList, packageDump: packageDump, process: processRows.replacingOccurrences(of: "10123 4321", with: "10124 4321"), pid: "4321") == nil)
    ck(systemUIIdentity(packageList: packageList, packageDump: packageDump, process: processRows.replacingOccurrences(of: "com.android.systemui", with: "arbitrary.app"), pid: "4321") == nil)
    let vivoFocus = "mCurrentFocus=Window{abc u0 NotificationShade fixture title}"
    let vivoWindow = "Window #0 Window{abc u0 NotificationShade fixture title}:\n  mDisplayId=0\n  mOwnerUid=10123\n  mSession=Session{def 4321:u0a10123}\n  mAttrs={ty=NOTIFICATION_SHADE}"
    ck(focusObservation(windows: vivoWindow, displays: "  Display: mDisplayId=0\n  " + vivoFocus).line == vivoFocus)
    ck(focusObservation(windows: vivoWindow, displays: "  Display: mDisplayId=0\nmIsDensityForced=true\n  " + vivoFocus).line == vivoFocus)
    let vivoTarget = PinTarget(window: vivoFocus, field: "", count: 0)
    ck(verifiedWindow(vivoWindow, target: vivoTarget, pid: "4321", uid: 10123))
    let numericRoleWindow = vivoWindow.replacingOccurrences(of: "ty=NOTIFICATION_SHADE", with: "ty=2040")
    ck(verifiedWindow(numericRoleWindow, target: vivoTarget, pid: "4321", uid: 10123))
    for role in ["2041", "02040", "2040suffix", "2040.0", "NOTIFICATION_SHADEextra", "NOTIFICATION_SHADE!", "", "2040 ty=", "2040 ty=2040", "NOTIFICATION_SHADE ty="] {
        ck(!verifiedWindow(vivoWindow.replacingOccurrences(of: "ty=NOTIFICATION_SHADE", with: "ty=" + role), target: vivoTarget, pid: "4321", uid: 10123))
    }
    ck(!verifiedWindow(numericRoleWindow, target: vivoTarget, pid: "9999", uid: 10123))
    ck(!verifiedWindow(numericRoleWindow, target: vivoTarget, pid: "4321", uid: 10124))
    let unverifiedOEMField = xml.replacingOccurrences(of: "id/pinEntry", with: "id/passwordEntry").replacingOccurrences(of: "password=\"true\"", with: "password=\"true\" editable=\"true\" input-type=\"18\" max-text-length=\"-1\"")
    ck(pinTarget(xml: unverifiedOEMField, windowText: focus) == nil)
    func flymeFixture(_ count: Int, deleteVisible: Bool) -> String {
        func container(_ id: String, _ cls: String, _ children: String, bounds: String = "[0,0][800,1600]") -> String {
            "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/\(id)\" class=\"\(cls)\" enabled=\"true\" password=\"false\" focused=\"false\" clickable=\"false\" bounds=\"\(bounds)\">\(children)</node>"
        }
        let field = "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/passwordEntry\" class=\"android.widget.EditText\" password=\"true\" enabled=\"true\" focused=\"true\" focusable=\"true\" clickable=\"false\" editable=\"true\" input-type=\"16\" max-text-length=\"-1\" text=\"\(String(repeating: "•", count: count))\" bounds=\"[250,200][550,260]\"/>"
        let delete = deleteVisible ? container("delete", "android.widget.ImageView", "", bounds: "[580,200][620,260]") : ""
        var tree = container("inputBox", "android.widget.RelativeLayout", field + delete)
        tree += container("lockPattern", "android.view.View", "", bounds: "[100,500][700,1400]").replacingOccurrences(of: "bounds=", with: "bounds-parent=\"[0,0][600,900]\" bounds=")
        let chain = [("keyguard_bouncer_container", "android.widget.FrameLayout"), ("keyguard_host_view", "android.widget.FrameLayout"), ("keyguard_security_container", "android.widget.FrameLayout"), ("view_flipper", "android.widget.ViewFlipper"), ("mz_keyguard_pin_view", "android.widget.LinearLayout"), ("keyguard_bouncer_frame", "android.widget.FrameLayout"), ("keyguard_bouncer_rl", "android.widget.RelativeLayout")]
        for (id, cls) in chain.reversed() { tree = container(id, cls, tree) }
        return "<?xml version=\"1.0\"?><hierarchy>" + tree + "</hierarchy>"
    }
    ck(flymeSpeechDisabled("0\n") && flymeSpeechDisabled("null"))
    ck(!flymeSpeechDisabled("1") && !flymeSpeechDisabled(nil) && !flymeSpeechDisabled(""))
    ck(batchArguments("SYNTHETIC", commands: [flymeSpeechCommand]) != nil)
    ck(batchArguments("SYNTHETIC", commands: identityCommands + [processCommand("123")!] + stateCommands + [flymeCodeCommand, flymePrivateModeCommand, flymeSpeechCommand]) != nil)
    ck(progressHeader("__AU_FLYME_V1__ 1 1 0 24", sequence: 1) == FlymeProgressHeader(sequence: 1, count: 1, error: 0, length: 24))
    for line in ["__AU_FLYME_V1__ 2 1 0 24", "__AU_FLYME_V1__ 1 5 0 24", "__AU_FLYME_V1__ 1 1 0 262145", "__AU_FLYME_V1__ 1 1 3 24", "__AU_FLYME_V1__ 1 01 0 24", "__AU_FLYME_V1__ 1 1 0 24 extra"] { ck(progressHeader(line, sequence: 1) == nil) }
    ck(flymeMaskedProgress("", observedCount: 1) == 1)
    ck(flymeMaskedProgress("•", observedCount: 1) == 1)
    ck(flymeMaskedProgress("", observedCount: nil) == 0)
    ck(flymeMaskedProgress("•", observedCount: 2) == nil)
    ck(flymeMaskedProgress("PRIVATE_NEGATIVE_MARKER", observedCount: 1) == nil)
    ck(flymeMaskedProgress("", observedCount: 0) == nil)
    let themeFrame = flymeFixture(0, deleteVisible: true)
    ck(pinTarget(xml: themeFrame, windowText: focus) == nil)
    ck(pinTarget(delegate: parseHierarchy(themeFrame, flymeProgressCount: 1)!, windowText: focus)?.count == 1)
    ck(pinTarget(delegate: parseHierarchy(flymeFixture(0, deleteVisible: false), flymeProgressCount: 1)!, windowText: focus) == nil)
    let flymeEmpty = flymeFixture(0, deleteVisible: false)
    let flymeTarget = pinTarget(xml: flymeEmpty, windowText: focus)
    ck(flymeTarget?.mode == .flymeFour && flymeTarget?.count == 0)
    ck(flymeTarget?.keys.count == 10 && flymeTarget?.keys[0]?.center.0 == 400 && flymeTarget?.keys[0]?.center.1 == 1287)
    ck(flymeTarget?.keys[1]?.center.0 == 200 && flymeTarget?.keys[1]?.center.1 == 612)
    for local in ["[0,0][599,900]", "[0,0][600,899]", "[1,0][601,900]", "[0,1][600,901]", ""] {
        ck(pinTarget(xml: flymeEmpty.replacingOccurrences(of: "[0,0][600,900]", with: local), windowText: focus) == nil)
    }
    ck(flymeTouchKeys(screen: UIBounds(x1: 0, y1: 0, x2: 600, y2: 20), local: UIBounds(x1: 0, y1: 0, x2: 600, y2: 20)) == nil)
    for count in 1...4 { ck(pinTarget(xml: flymeFixture(count, deleteVisible: true), windowText: focus)?.count == count) }
    ck(pinTarget(xml: flymeFixture(0, deleteVisible: true), windowText: focus) == nil)
    ck(pinTarget(xml: flymeFixture(1, deleteVisible: false), windowText: focus) == nil)
    ck(pinTarget(xml: flymeFixture(5, deleteVisible: true), windowText: focus) == nil)
    for (old, new) in [("input-type=\"16\"", "input-type=\"18\""), ("editable=\"true\"", "editable=\"false\""), ("id/mz_keyguard_pin_view", "id/mz_keyguard_password_view"), ("id/keyguard_host_view", "id/unknown_host"), ("id/lockPattern", "id/unknown_keyboard"), ("text=\"\"", "text=\"x\""), ("[250,200][550,260]", "[0,0][900,1800]")] {
        ck(pinTarget(xml: flymeEmpty.replacingOccurrences(of: old, with: new), windowText: focus) == nil)
    }
    ck(pinTarget(xml: flymeEmpty.replacingOccurrences(of: "package=\"com.android.systemui\"", with: "package=\"example.other\""), windowText: focus) == nil)
    var flymeState = s; flymeState.target = flymeTarget
    var currentProof = flymeState; currentProof.focusResult = "focus_identity_verified"; currentProof.focusDisplayID = 0
    currentProof.postUIStateChecked = true; currentProof.observedAt = 100; currentProof.postUIVerifiedAt = 101
    ck(freshFlymeInputProof(currentProof, expected: 0, now: 102))
    ck(!freshFlymeInputProof(currentProof, expected: 0, now: 102.001))
    ck(!freshFlymeInputProof(currentProof, expected: 1, now: 101))
    currentProof.postUIStateChecked = false; ck(!freshFlymeInputProof(currentProof, expected: 0, now: 101))

    var flymeActions = 0; var flymeFinalChecks = 0
    ck(drivePIN(Data(repeating: 48, count: 4), initial: flymeState, observe: { final in
        var next = flymeState
        if final { flymeFinalChecks += 1; next.state = .unlocked; next.target = nil }
        else { next.target = pinTarget(xml: flymeFixture(flymeActions, deleteVisible: flymeActions > 0), windowText: focus) }
        return next
    }, send: { key in ck(key != 66); flymeActions += 1; return true }) == .submitted)
    ck(flymeActions == 4 && flymeFinalChecks == 1)
    flymeActions = 0
    ck(drivePIN(Data(repeating: 48, count: 4), initial: flymeState, observe: { _ in flymeState }, send: { _ in flymeActions += 1; return true }) == .partial && flymeActions == 1)
    ck(drivePIN(Data(repeating: 48, count: 6), initial: flymeState, observe: { _ in flymeState }, send: { _ in fatalError("length gate failed") }) == .refused)
    ck(flymeSystemUICodeMatches(flymeSystemUISHA256 + "  " + flymeSystemUIPath + "\n"))
    ck(!flymeSystemUICodeMatches(String(repeating: "0", count: 64) + "  " + flymeSystemUIPath))
    ck(!flymeSystemUICodeMatches(flymeSystemUISHA256 + "  " + flymeSystemUIPath + "\nextra"))
    ck(batchArguments("SYNTHETIC", commands: [flymeCodeCommand]) != nil)
    ck(batchArguments("SYNTHETIC", commands: [flymePrivateModeCommand]) != nil)
    ck(batchArguments("SYNTHETIC", commands: identityCommands + [processCommand("123")!] + stateCommands + [flymeCodeCommand, flymePrivateModeCommand]) != nil)
    ck(batchArguments("SYNTHETIC", commands: [("flymePrivateMode", "settings put global mz_private_mode 0")]) == nil)
    for value in ["0", "null\n"] { ck(flymePrivateModeDisabled(value)) }
    for value in [nil, "", "1", "-1", "00", "0\n1", "error"] as [String?] { ck(!flymePrivateModeDisabled(value)) }
    var privateBlocked = flymeState; privateBlocked.reason = "flyme_private_mode_unverified"; privateBlocked.target = nil
    ck(attempt(flymeState, authorized: true, recheck: { privateBlocked }, read: { fatalError("private-mode gate read a credential") }, submit: { fatalError("private-mode gate sent input") }, confirm: { privateBlocked }).0 == "state_changed_before_secret")
    var flymeNonempty = flymeState; flymeNonempty.target = pinTarget(xml: flymeFixture(1, deleteVisible: true), windowText: focus)
    ck(decision(flymeNonempty) == "pin_field_not_empty")
    flymeActions = 0
    ck(drivePIN(Data(repeating: 48, count: 4), initial: flymeState, observe: { _ in
        var next = flymeState; next.target = pinTarget(xml: flymeFixture(flymeActions, deleteVisible: flymeActions > 0), windowText: focus); return next
    }, send: { key in ck(key != 66); flymeActions += 1; return true }) == .partial && flymeActions == 4)
    let flymeCoverXML = "<?xml version=\"1.0\"?><hierarchy>" +
        ["keyguard_background_frame", "keyguard_header", "keyguard_selector_fade_container"].map { id in
            let cls = id == "keyguard_header" ? "android.widget.RelativeLayout" : "android.widget.FrameLayout"
            let bounds = id == "keyguard_header" ? "[0,0][800,100]" : id == "keyguard_background_frame" ? "[0,0][800,1600]" : "[0,1500][800,1600]"
            return "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/\(id)\" class=\"\(cls)\" enabled=\"true\" password=\"false\" focused=\"false\" clickable=\"false\" bounds=\"\(bounds)\"/>"
        }.joined() + "</hierarchy>"
    ck(parseHierarchy(flymeCoverXML)?.flymeCover == true && coverHierarchy(flymeCoverXML))
    ck(parseHierarchy(flymeCoverXML.replacingOccurrences(of: "id/keyguard_selector_fade_container", with: "id/unknown_footer"))?.flymeCover == false)
    var metadataState = flymeState; metadataState.focusResult = "focus_identity_verified"; metadataState.postUIStateChecked = true
    metadataState.observedAt = 10; metadataState.postUIVerifiedAt = 11
    metadataState.target = PinTarget(window: "PRIVATE_MARKER", field: "PRIVATE_MARKER", count: 1, mode: .flymeFour)
    let safeMetadata = pinInputMetadata(metadataState, actions: 1, adbSucceeded: 1, now: 11)
    ck(safeMetadata["observedEnteredCount"] as? Int == 1 && !String(data: try! JSONSerialization.data(withJSONObject: safeMetadata), encoding: .utf8)!.contains("PRIVATE_MARKER"))
    ck(pinInputMetadata(metadataState, actions: 1, adbSucceeded: 1, now: 13)["observedEnteredCount"] == nil)
    ck(!verifiedWindow(vivoWindow.replacingOccurrences(of: "u0a10123", with: "u0a74"), target: vivoTarget, pid: "4321", uid: 10123))
    ck(!verifiedWindow(vivoWindow.replacingOccurrences(of: "ty=NOTIFICATION_SHADE", with: "ty=APPLICATION"), target: vivoTarget, pid: "4321", uid: 10123))
    ck(!verifiedWindow(vivoWindow.replacingOccurrences(of: "mOwnerUid=10123", with: "mOwnerUid=10124"), target: vivoTarget, pid: "4321", uid: 10123))
    let vivoCover = "<?xml version=\"1.0\"?><hierarchy><node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/keyguard_header\" class=\"android.widget.RelativeLayout\" enabled=\"true\" password=\"false\" focused=\"false\"/></hierarchy>"
    ck(coverHierarchy(vivoCover)); ck(!coverHierarchy(vivoCover.replacingOccurrences(of: "android.widget.RelativeLayout", with: "android.widget.EditText")))
    ck(!coverHierarchy(vivoCover.replacingOccurrences(of: "</hierarchy>", with: "<node package=\"com.android.systemui\" resource-id=\"unknown\" password=\"true\" focused=\"false\"/></hierarchy>")))
    func node(_ id: String, _ cls: String, focused: Bool = false, clickable: Bool = false, desc: String = "", children: String = "") -> String {
        let bounds: String
        if id.hasPrefix("VivoPinkey"), let digit = Int(id.dropFirst("VivoPinkey".count)) {
            let x = 100 + digit % 3 * 300; let y = 1300 + digit / 3 * 250
            bounds = "[\(x),\(y)][\(x + 200),\(y + 200)]"
        } else if id.hasPrefix("password"), let digit = Int(id.dropFirst(8).replacingOccurrences(of: "bg", with: "")) {
            let x = 100 + digit * 100; bounds = "[\(x),900][\(x + 50),950]"
        } else if id == "vivo_pin_keyboard" { bounds = "[0,1200][1260,2400]" }
        else { bounds = "[0,0][1260,2800]" }
        return "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/\(id)\" class=\"\(cls)\" enabled=\"true\" password=\"false\" focused=\"\(focused)\" focusable=\"\(focused || clickable)\" clickable=\"\(clickable)\" text=\"\" content-desc=\"\(desc)\" bounds=\"\(bounds)\">\(children)</node>"
    }
    let slots = (1...6).map { node("password\($0)", "android.widget.FrameLayout", children: node("password\($0)bg", "android.widget.FrameLayout")) }.joined()
    let keys = (0...9).map { node("VivoPinkey\($0)", "android.view.ViewGroup", clickable: true) }.joined()
    let keyboard = node("vivo_pin_keyboard", "android.widget.LinearLayout", children: keys)
    let oemPIN = "<?xml version=\"1.0\"?><hierarchy>" + node("keyguard_bouncer_container", "android.widget.FrameLayout", children: node("keyguard_security_container", "android.view.ViewGroup", children: node("vivo_pin_view", "android.widget.RelativeLayout", focused: true, desc: "已输入0位", children: slots + keyboard))) + "</hierarchy>"
    let oemTarget = pinTarget(xml: oemPIN, windowText: vivoFocus)
    ck(oemTarget?.mode == .vivoSix && oemTarget?.count == 0)
    func filledFixture(_ count: Int, missing: [Int]) -> String {
        let changed = (1...6).map { i -> String in
            let background = node("password\(i)bg", "android.widget.FrameLayout")
            return missing.contains(i) ? background : node("password\(i)", "android.widget.FrameLayout", children: background)
        }.joined()
        return oemPIN.replacingOccurrences(of: slots, with: changed).replacingOccurrences(of: "已输入0位", with: "entered \(count) digits")
    }
    let filledPrefix = filledFixture(1, missing: [1])
    let prefixTarget = pinTarget(xml: filledPrefix, windowText: vivoFocus)
    ck(prefixTarget?.count == 1 && prefixTarget?.placeholder == oemTarget?.placeholder)
    var nonemptyPrefix = s; nonemptyPrefix.target = prefixTarget
    ck(decision(nonemptyPrefix) == "pin_field_not_empty")
    ck(pinTarget(xml: filledFixture(2, missing: [1, 2]), windowText: vivoFocus)?.count == 2)
    ck(pinTarget(xml: filledFixture(6, missing: Array(1...6)), windowText: vivoFocus)?.count == 6)
    let missingSuffix = filledFixture(1, missing: [2])
    ck(pinTarget(xml: missingSuffix, windowText: vivoFocus) == nil)
    ck(pinTarget(xml: filledFixture(0, missing: [1]), windowText: vivoFocus) == nil)
    ck(pinTarget(xml: filledPrefix.replacingOccurrences(of: "password1bg", with: "unknown_bg"), windowText: vivoFocus) == nil)
    let background = node("password1bg", "android.widget.FrameLayout")
    ck(pinTarget(xml: filledPrefix.replacingOccurrences(of: background, with: background + background), windowText: vivoFocus) == nil)
    let foreground = node("password1", "android.widget.FrameLayout")
    ck(pinTarget(xml: filledPrefix.replacingOccurrences(of: keyboard, with: foreground + foreground + keyboard), windowText: vivoFocus) == nil)
    let overlappingBackground = background.replacingOccurrences(of: "[200,900][250,950]", with: "[200,1300][250,1350]")
    ck(pinTarget(xml: filledPrefix.replacingOccurrences(of: background, with: overlappingBackground), windowText: vivoFocus) == nil)
    let changedBackground = background.replacingOccurrences(of: "[200,900][250,950]", with: "[201,900][251,950]")
    ck(pinTarget(xml: filledFixture(1, missing: []).replacingOccurrences(of: background, with: changedBackground), windowText: vivoFocus) == nil)
    let invalidForeground = foreground.replacingOccurrences(of: "enabled=\"true\"", with: "enabled=\"false\"")
    ck(pinTarget(xml: filledPrefix.replacingOccurrences(of: keyboard, with: invalidForeground + keyboard), windowText: vivoFocus) == nil)
    ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "已输入0位", with: "entered 3 digits"), windowText: vivoFocus)?.count == 3)
    for description in ["", "0", "已输入7位", "已输入0位 entered 0 digits", "已输入100位"] {
        ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "已输入0位", with: description), windowText: vivoFocus) == nil)
    }
    ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "com.android.systemui\"", with: "arbitrary.app\""), windowText: vivoFocus) == nil)
    ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "password6bg", with: "unknown"), windowText: vivoFocus) == nil)
    ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "VivoPinkey9", with: "VivoPinkey8"), windowText: vivoFocus) == nil)
    ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "keyguard_security_container", with: "arbitrary_container"), windowText: vivoFocus) == nil)
    let strongCover = vivoCover.replacingOccurrences(of: "</hierarchy>", with: node("vivo_keyguard_overlay", "android.widget.FrameLayout") + node("vivo_keyguard_host_container", "android.widget.FrameLayout") + node("plugin", "android.widget.RelativeLayout").replacingOccurrences(of: "com.android.systemui:id/plugin", with: "com.vivo.systemuiplugin:id/keyguard_os5") + node("calendar", "android.widget.TextView", focused: true).replacingOccurrences(of: "com.android.systemui:id/calendar", with: "com.vivo.systemuiplugin:id/lunar_info_first_line") + "</hierarchy>")
    ck(coverHierarchy(strongCover))
    ck(!coverHierarchy(strongCover.replacingOccurrences(of: "lunar_info_first_line", with: "notification_reply")))
    ck(!coverHierarchy(strongCover.replacingOccurrences(of: "android.widget.TextView", with: "android.widget.EditText")))
    ck(!coverHierarchy(strongCover.replacingOccurrences(of: "vivo_keyguard_host_container", with: "missing")))
    var oemState = s; oemState.target = oemTarget
    var emitted: [Int] = []; var finalQueries = 0
    let oemResult = drivePIN(Data("012345".utf8), initial: oemState, observe: { final in
        var next = oemState
        if final { finalQueries += 1; next.state = .unlocked; next.target = nil }
        else { next.target = PinTarget(window: oemTarget!.window, field: oemTarget!.field, count: emitted.count, mode: .vivoSix) }
        return next
    }, send: { emitted.append($0); return true })
    ck(oemResult == .submitted && emitted == [7,8,9,10,11,12] && finalQueries == 1 && !emitted.contains(66))
    emitted = []
    ck(drivePIN(Data("012345".utf8), initial: oemState, observe: { final in
        var next = oemState; next.target = PinTarget(window: oemTarget!.window, field: oemTarget!.field, count: emitted.count, mode: .vivoSix); return next
    }, send: { emitted.append($0); return true }) == .partial && emitted.count == 6 && !emitted.contains(66))
    emitted = []
    ck(drivePIN(Data("0123".utf8), initial: oemState, observe: { _ in oemState }, send: { emitted.append($0); return true }) == .refused && emitted.isEmpty)
    ck(!coverHierarchy(strongCover.replacingOccurrences(of: "clickable=\"false\" text", with: "clickable=\"true\" text")))
    emitted = []
    ck(drivePIN(Data("012345".utf8), initial: oemState, observe: { final in
        var next = oemState
        next.target = PinTarget(window: oemTarget!.window, field: oemTarget!.field, count: emitted.count, mode: .vivoSix)
        if final { next.reason = "keyguard_ambiguous" }
        return next
    }, send: { emitted.append($0); return true }) == .partial && emitted.count == 6 && !emitted.contains(66))
    let namespacedFocus = vivoFocus.replacingOccurrences(of: "Window{abc", with: "Window{com.android.systemui:ab12cd3")
    let namespacedWindow = vivoWindow.replacingOccurrences(of: "Window{abc", with: "Window{com.android.systemui:ab12cd3")
    let namespacedDisplay = "  Display: mDisplayId=0\n  " + namespacedFocus
    ck(focusObservation(windows: namespacedWindow, displays: namespacedDisplay).line == namespacedFocus)
    let namespacedTarget = pinTarget(xml: oemPIN, windowText: namespacedFocus)
    ck(namespacedTarget?.window == namespacedFocus && namespacedTarget?.mode == .vivoSix)
    ck(verifiedWindow(namespacedWindow, target: namespacedTarget!, pid: "4321", uid: 10123))
    ck(focusObservation(windows: namespacedWindow.replacingOccurrences(of: "com.android.systemui:ab12cd3", with: "arbitrary.app:ab12cd3"), displays: namespacedDisplay.replacingOccurrences(of: "com.android.systemui:ab12cd3", with: "arbitrary.app:ab12cd3")).line == nil)
    ck(pinTarget(xml: oemPIN, windowText: namespacedFocus.replacingOccurrences(of: "com.android.systemui:ab12cd3", with: "arbitrary.app:ab12cd3")) == nil)
    let siblingPackages = "package:com.android.systemui.plugin.globalactions.wallet uid:10234\npackage:com.android.systemui.accessibility.accessibilitymenu uid:10345\n"
    let livePackageRows = packageList + siblingPackages
    let livePackageDump = packageDump.replacingOccurrences(of: "(abc)", with: "(bc23de4)") + "    privatePkgFlags=[ PRIVILEGED ]\n"
    ck(systemUIIdentity(packageList: livePackageRows, packageDump: livePackageDump, process: processRows, pid: "4321") == trusted)
    ck(systemUIIdentity(packageList: siblingPackages, packageDump: livePackageDump, process: processRows, pid: "4321") == nil)
    ck(systemUIIdentity(packageList: livePackageRows + packageList, packageDump: livePackageDump, process: processRows, pid: "4321") == nil)
    ck(systemUIIdentity(packageList: livePackageRows.replacingOccurrences(of: "systemui uid:10123", with: "systemui uid:invalid"), packageDump: livePackageDump, process: processRows, pid: "4321") == nil)
    ck(systemUIIdentity(packageList: livePackageRows + "package:com.android.systemui\n", packageDump: livePackageDump, process: processRows, pid: "4321") == nil)
    ck(systemUIIdentity(packageList: livePackageRows.replacingOccurrences(of: "systemui uid:10123", with: "systemui uid:10234"), packageDump: livePackageDump, process: processRows, pid: "4321") == nil)
    ck(oemTarget?.keys.count == 10 && oemTarget?.placeholder != nil)
    ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "[100,1300][300,1500]", with: "[9999,1300][10199,1500]"), windowText: vivoFocus) == nil)
    ck(pinTarget(xml: oemPIN.replacingOccurrences(of: "[400,1300][600,1500]", with: "[100,1300][300,1500]"), windowText: vivoFocus) == nil)
    ck(vivoCoverBounds(strongCover) != nil)
    ck(vivoCoverBounds(unsafeCoverXML) == nil)
    ck(activityEligible(oemState, authorized: true)); ck(!activityEligible(oemState, authorized: false))
    var notEmpty = oemState; notEmpty.target = PinTarget(window: oemTarget!.window, field: oemTarget!.field, count: 1, mode: .vivoSix, keys: oemTarget!.keys, placeholder: oemTarget!.placeholder)
    ck(!activityEligible(notEmpty, authorized: true))
    var unsafeActivity = oemState; unsafeActivity.awake = false; ck(!activityEligible(unsafeActivity, authorized: true))
    unsafeActivity = oemState; unsafeActivity.user = 10; ck(!activityEligible(unsafeActivity, authorized: true))
    unsafeActivity = oemState; unsafeActivity.reason = "unknown"; ck(!activityEligible(unsafeActivity, authorized: true))
    ck(!activityEligible(unlocked, authorized: true))
    var pinProof = oemState; pinProof.serial = "synthetic"
    pinProof.observedAt = 100; pinProof.postUIVerifiedAt = 101; pinProof.postUIStateChecked = true
    pinProof.focusResult = "focus_identity_verified"; pinProof.focusSource = "displays"; pinProof.focusDisplayID = 0
    pinProof.hierarchyResult = "hierarchy_xml_parsed"; pinProof.hierarchyStdoutEmpty = false
    ck(immediateTrustedPinActivityObservation(pinProof, serial: "synthetic", authorized: true, now: 101.1))
    ck(immediateTrustedPinActivityObservation(pinProof, serial: "synthetic", authorized: true, now: 102))
    ck(!immediateTrustedPinActivityObservation(pinProof, serial: "synthetic", authorized: true, now: 102.001))
    ck(!immediateTrustedPinActivityObservation(pinProof, serial: "other", authorized: true, now: 101.1))
    ck(!immediateTrustedPinActivityObservation(pinProof, serial: "synthetic", authorized: false, now: 101.1))
    func deniesPinProof(_ change: (inout Snapshot) -> Void) -> Bool {
        var altered = pinProof; change(&altered)
        return !immediateTrustedPinActivityObservation(altered, serial: "synthetic", authorized: true, now: 101.1)
    }
    ck(deniesPinProof { $0.postUIStateChecked = false })
    ck(deniesPinProof { $0.postUIVerifiedAt = 0 })
    ck(deniesPinProof { $0.postUIVerifiedAt = 102 })
    ck(deniesPinProof { $0.observedAt = 0 })
    ck(deniesPinProof { $0.focusResult = "focus_unverified" })
    ck(deniesPinProof { $0.focusDisplayID = 1 })
    ck(deniesPinProof { $0.user = 10 })
    ck(deniesPinProof { $0.secure = false })
    ck(deniesPinProof { $0.awake = false })
    ck(deniesPinProof { $0.bootComplete = false })
    ck(deniesPinProof { $0.userUnlocked = false })
    ck(deniesPinProof { $0.hierarchyResult = "not_queried" })
    ck(deniesPinProof { s in let old = s.target!; s.target = PinTarget(window: old.window, field: old.field, count: 1, mode: old.mode, keys: old.keys, placeholder: old.placeholder) })
    ck(deniesPinProof { $0.target?.mode = .aosp })
    ck(deniesPinProof { s in let old = s.target!; s.target = PinTarget(window: "mCurrentFocus=Window{abc u1 NotificationShade}", field: old.field, count: old.count, mode: old.mode, keys: old.keys, placeholder: old.placeholder) })
    ck(deniesPinProof { $0.target?.placeholder = nil })
    ck(deniesPinProof { $0.target?.placeholder = UIBounds(x1: 0, y1: 0, x2: 0, y2: 0) })
    ck(deniesPinProof { s in let key = s.target?.keys[0]; s.target?.placeholder = key })

    let wrappedCover = "UIAutomation fixture informational prefix\n" + strongCover + "\nUI hierchary dumped to: /proc/self/fd/1\n"
    ck(vivoCoverBounds(wrappedCover) == vivoCoverBounds(strongCover) && vivoCoverBounds(wrappedCover) != nil)
    ck(coverHierarchy(wrappedCover, requireVivo: true)); ck(!coverHierarchy(coverXML, requireVivo: true))
    ck(vivoCoverBounds("UI hierchary dumped to: /proc/self/fd/1") == nil)
    ck(vivoCoverBounds(wrappedCover.replacingOccurrences(of: "</hierarchy>", with: "</broken>")) == nil)
    ck(vivoCoverBounds(wrappedCover.replacingOccurrences(of: "<hierarchy>", with: "<!DOCTYPE hierarchy><hierarchy>")) == nil)
    ck(collectorResourceResult(nil) == "hierarchy_collector_resource_missing")
    ck(collectorResourceResult(Data("wrong-code".utf8)) == "hierarchy_collector_resource_mismatch")
    let codeResource = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(helperAppName + ".app/Contents/Resources/fast-reader.jar")
    ck(collectorResourceResult(try? Data(contentsOf: codeResource)) == "verified")
    ck(!collectorDeviceHashMatches(""))
    ck(collectorDeviceHashMatches(collectorSHA256 + "  " + collectorDevicePath + "\n"))
    ck(!collectorDeviceHashMatches(String(repeating: "0", count: 64) + "  " + collectorDevicePath))
    ck(!collectorDeviceHashMatches(collectorSHA256 + "  /data/local/tmp/arbitrary.jar"))
    ck(!collectorDeviceHashMatches(collectorSHA256 + "  " + collectorDevicePath + "\n" + collectorSHA256 + "  " + collectorDevicePath))
    let readerArgs = fastReaderArguments("fixture")!
    ck(readerArgs.prefix(2) == ["-s", "fixture"] && readerArgs.contains("-T") && readerArgs.contains("none"))
    ck(readerArgs.last!.contains("uiautomator runtest " + collectorDevicePath) && !readerArgs.last!.contains("uiautomator dump"))
    ck(readerArgs.last!.hasSuffix("| /system/bin/cat'") && readerArgs.contains("4"))
    ck(fastReaderArguments("x;unsafe") == nil)
    ck(hierarchyDiagnostic(Data("collector_blocked:root_query:null_root".utf8), stderr: Data(), ok: true) == "hierarchy_collector_root_query_blocked")
    ck(hierarchyDiagnostic(Data("collector_blocked:unknown_stage:unknown_failure".utf8), stderr: Data(), ok: true) == "hierarchy_collector_blocked")
    var cached = s; cached.observedAt = 100
    let cacheWindow = cached.target!.window
    ck(uiReuse(cached, s, window: cacheWindow, now: 102) == .refresh)
    ck(uiReuse(cached, s, window: cacheWindow, now: 102.001) == .refresh)
    ck(cached.observedAt == 100)
    var readsUI = 0
    func observeCached(_ current: Snapshot, now: Double) -> Snapshot? {
        switch uiReuse(cached, current, window: cacheWindow, now: now) {
        case .blocked: return nil
        case .reuse: return cached
        case .refresh: readsUI += 1; var fresh = current; fresh.observedAt = now; return fresh
        }
    }
    ck(observeCached(s, now: 101)?.observedAt == 101 && readsUI == 1)
    ck(observeCached(s, now: 103)?.observedAt == 103 && readsUI == 2)
    var disagreement = s; disagreement.user = 10
    ck(observeCached(disagreement, now: 103) == nil && readsUI == 2)
    ck(uiReuse(cached, s, window: "other", now: 103) == .blocked)
    disagreement = s; disagreement.secure = false
    ck(observeCached(disagreement, now: 103) == nil && readsUI == 2)
    disagreement = s; disagreement.reason = "unknown"
    ck(observeCached(disagreement, now: 103) == nil && readsUI == 2)
    ck(uiReuse(cached, s, window: cacheWindow, now: 99) == .blocked)
    ck(existingAuthorizationEligible(unlocked)); ck(!existingAuthorizationEligible(s))
    disagreement = unlocked; disagreement.online = false; ck(!existingAuthorizationEligible(disagreement))
    disagreement = unlocked; disagreement.user = 10; ck(!existingAuthorizationEligible(disagreement))
    disagreement = unlocked; disagreement.awake = false; ck(!existingAuthorizationEligible(disagreement))
    var credentialQueries = 0; var interactionModes: [Bool] = []
    func fixtureRead(_ interactive: Bool = false, interactionStatus: Int32 = 0, queryStatus: Int32 = 0, item: Any? = Data("2468".utf8)) -> CredentialRead {
        readCredential(interactive: interactive, setInteraction: { mode in interactionModes.append(mode); return interactionStatus }, query: {
            credentialQueries += 1; return (queryStatus, item)
        })
    }
    var cr = fixtureRead(interactionStatus: -25291)
    ck(cr.pin == nil && cr.metadata.stage == .interaction && cr.metadata.status == -25291 && credentialQueries == 0)
    cr = fixtureRead(queryStatus: -25308)
    ck(cr.pin == nil && cr.metadata.stage == .query && cr.metadata.status == -25308 && credentialQueries == 1)
    cr = fixtureRead(item: "not_data")
    ck(cr.pin == nil && cr.metadata.stage == .returnedType && cr.metadata.status == 0 && credentialQueries == 2)
    cr = fixtureRead(item: Data("invalid".utf8))
    ck(cr.pin == nil && cr.metadata.stage == .pinFormat && credentialQueries == 3)
    cr = fixtureRead()
    ck(cr.pin != nil && cr.metadata.stage == .success && cr.metadata.status == 0 && credentialQueries == 4)
    cr.pin!.resetBytes(in: 0..<cr.pin!.count); cr.pin = nil
    ck(interactionModes.allSatisfy { !$0 })
    var verificationReads = 0
    var auth = verifyExistingAuthorization(interactiveRead: { fixtureRead(true, queryStatus: -128) }, noninteractiveRead: {
        verificationReads += 1; return fixtureRead()
    })
    ck(auth.result == "credential_authorization_blocked" && auth.diagnostics.count == 1 && verificationReads == 0)
    ck(auth.diagnostics.first?.status == -128 && interactionModes.last == false)
    auth = verifyExistingAuthorization(interactiveRead: { fixtureRead(true) }, noninteractiveRead: {
        verificationReads += 1; return fixtureRead(queryStatus: -25308)
    })
    ck(auth.result == "credential_authorized_noninteractive_blocked" && verificationReads == 1 && auth.diagnostics.count == 2 && auth.proofScope == "interactive_read_only")
    ck(auth.diagnostics.last?.stage == .query && auth.diagnostics.last?.status == -25308 && !auth.diagnostics.last!.interactive)
    auth = verifyExistingAuthorization(interactiveRead: { fixtureRead(true) }, noninteractiveRead: {
        verificationReads += 1; return fixtureRead()
    })
    ck(auth.result == "credential_authorized" && verificationReads == 2 && auth.proofScope == "same_process_noninteractive_only")
    ck(auth.diagnostics.map { $0.interactive } == [true, false])
    let receiptData = try! JSONSerialization.data(withJSONObject: auth.diagnostics.map { $0.json }, options: [.sortedKeys])
    let receiptText = String(decoding: receiptData, as: UTF8.self)
    ck(!receiptText.contains("2468") && !receiptText.contains("pin") && !receiptText.contains("length"))
    ck(Set(auth.diagnostics[0].json.keys) == Set(["stage", "osStatus", "mode"]))
    let framed = Data("__AU_BEGIN_user__\n0\n\n__AU_END_user__:0\n__AU_BEGIN_policy__\nfixture\n\n__AU_END_policy__:0\n".utf8)
    ck(parseBatch(framed, names: ["user", "policy"])?["user"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    for text in [String(decoding: framed, as: UTF8.self).replacingOccurrences(of: "__AU_END_user__:0", with: "__AU_END_user__:1"),
                 String(decoding: framed, as: UTF8.self).replacingOccurrences(of: "__AU_END_user__:0", with: "__AU_END_user__:0\n__AU_END_user__:0"),
                 String(decoding: framed, as: UTF8.self).replacingOccurrences(of: "__AU_BEGIN_policy__", with: "__AU_BEGIN_other__"), "__AU_BEGIN_user__\n0"] {
        ck(parseBatch(Data(text.utf8), names: ["user", "policy"]) == nil)
    }
    ck(parseBatch(framed, names: ["user", "user"]) == nil)
    ck(batchArguments("fixture", commands: [("user", "am get-current-user; input tap 1 1")]) == nil)
    ck(processCommand("4321;sh") == nil); ck(processCommand("-1") == nil)
    let batch = batchArguments("fixture", commands: stateCommands)!
    ck(batch.last!.contains("au_status=$?") && batch.last!.contains("exit \"$au_status\""))
    ck(batch.last!.hasPrefix("'printf") && batch.last!.hasSuffix("'"))
    ck(postUICompatible(s, s, sameIdentity: true, uiObservedAt: 100, now: 102))
    ck(!postUICompatible(s, s, sameIdentity: true, uiObservedAt: 100, now: 102.001))
    ck(!postUICompatible(s, s, sameIdentity: false, uiObservedAt: 100, now: 101))
    var postChange = s; postChange.awake = false; ck(!postUICompatible(s, postChange, sameIdentity: true, uiObservedAt: 100, now: 101))
    postChange = s; postChange.user = 10; ck(!postUICompatible(s, postChange, sameIdentity: true, uiObservedAt: 100, now: 101))
    postChange = s; postChange.state = .unlocked; ck(!postUICompatible(s, postChange, sameIdentity: true, uiObservedAt: 100, now: 101))
    var actionProof = s; actionProof.target = nil; actionProof.coverWindow = focus
    actionProof.observedAt = 100; actionProof.postUIStateChecked = true; actionProof.postUIVerifiedAt = 101
    actionProof.focusResult = "focus_identity_verified"
    ck(immediateCoverObservation(actionProof, actionProof, now: 101.1))
    ck(!immediateCoverObservation(actionProof, actionProof, now: 102.001))
    var invalidProof = actionProof; invalidProof.postUIVerifiedAt = 0
    ck(!immediateCoverObservation(actionProof, invalidProof, now: 101.1))
    invalidProof = actionProof; invalidProof.postUIStateChecked = false
    ck(!immediateCoverObservation(actionProof, invalidProof, now: 101.1))
    invalidProof = actionProof; invalidProof.user = 10
    ck(!immediateCoverObservation(actionProof, invalidProof, now: 101.1))
    invalidProof = actionProof; invalidProof.coverWindow = "different"
    ck(!immediateCoverObservation(actionProof, invalidProof, now: 101.1))
    invalidProof = actionProof; invalidProof.awake = false
    ck(!immediateCoverObservation(actionProof, invalidProof, now: 101.1))
    invalidProof = actionProof; invalidProof.reason = "state_or_identity_changed_during_ui"
    ck(!immediateCoverObservation(actionProof, invalidProof, now: 101.1))
    invalidProof = actionProof; invalidProof.target = s.target
    ck(!immediateCoverObservation(actionProof, invalidProof, now: 101.1))
    let sharedCover = parseHierarchy(wrappedCover)!
    ck(coverHierarchy(sharedCover) == coverHierarchy(wrappedCover) && vivoCoverBounds(sharedCover) == vivoCoverBounds(wrappedCover))
    let sharedPIN = parseHierarchy(oemPIN)!
    ck(pinTarget(delegate: sharedPIN, windowText: vivoFocus) == pinTarget(xml: oemPIN, windowText: vivoFocus))
    ck(parseHierarchy(wrappedCover.replacingOccurrences(of: "<hierarchy>", with: "<!DOCTYPE hierarchy><hierarchy>")) == nil)
    ck(wmAuthenticationArguments("fixture") == ["-s", "fixture", "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/wm", "dismiss-keyguard"])
    ck(wmAuthenticationArguments("fixture;sh") == nil)
    ck(wmAuthenticationCommandOK(stdout: Data(), stderr: Data(), ok: true))
    ck(!wmAuthenticationCommandOK(stdout: Data(), stderr: Data(), ok: false))
    for message in ["SecurityException INJECT_EVENTS DO_NOT_LEAK", "Error: denied", "permission denied", "request failed"] {
        ck(!wmAuthenticationCommandOK(stdout: Data(), stderr: Data(message.utf8), ok: true))
        ck(!wmAuthenticationCommandOK(stdout: Data(message.utf8), stderr: Data(), ok: true))
    }
    var wmRequests = 0
    let wmFailed = prepare(cover, authorized: true, observe: { cover }, wake: { preconditionFailure("unexpected wake") }, afterWake: { cover },
        present: { wmRequests += 1; return wmAuthenticationCommandOK(stdout: Data(), stderr: Data("SecurityException".utf8), ok: true) },
        afterPresent: { preconditionFailure("failed WM must stop") })
    ck(wmFailed.result == "presentation_command_failed_no_retry" && wmRequests == 1)
    let wmUnauthorized = prepare(cover, authorized: false, observe: { preconditionFailure("noauth") }, wake: { false }, afterWake: { cover },
        present: { wmRequests += 1; return true }, afterPresent: { s })
    ck(wmUnauthorized.result == "authorization_required" && wmRequests == 1)
    let wmNotReady = prep(cover, presented: cover)
    ck(wmNotReady.result == "pin_page_unconfirmed_no_retry")
    ck(!wmAuthenticationCommandOK(stdout: Data("ERROR unavailable".utf8), stderr: Data(), ok: true))
    ck(uiReuse(cached, s, window: cacheWindow, now: 100.1) == .refresh)
    var cachedCover = cached; cachedCover.target = nil; cachedCover.coverWindow = cacheWindow
    ck(uiReuse(cachedCover, s, window: cacheWindow, now: 102) == .reuse)
    ck(uiReuse(cachedCover, s, window: cacheWindow, now: 102.001) == .refresh)
    ck(cached.observedAt == 100 && cachedCover.observedAt == 100)
    ck(!trustedADB()) // Test executable has no signed-bundle ADB configuration.
    func hyperosNode(_ id: String, _ cls: String, bounds: String, password: String = "false", focused: String = "false", clickable: String = "false", focusable: String = "false", text: String = "", children: String = "") -> String {
        "<node package=\"com.android.systemui\" resource-id=\"com.android.systemui:id/\(id)\" class=\"\(cls)\" enabled=\"true\" password=\"\(password)\" focused=\"\(focused)\" focusable=\"\(focusable)\" clickable=\"\(clickable)\" text=\"\(text)\" bounds=\"\(bounds)\">\(children)</node>"
    }
    func hyperosKeyBounds(_ digit: Int, overlap: Bool) -> String {
        if overlap && digit == 0 { return hyperosKeyBounds(5, overlap: false) }
        let pos = digit == 0 ? 10 : digit - 1
        let x1 = 100 + (pos % 3) * 230
        let y1 = 900 + (pos / 3) * 180
        return "[\(x1),\(y1)][\(x1 + 200),\(y1 + 150)]"
    }
    func hyperosFixture(bullets: Int = 0, deleteClickable: Bool = false, emergencyFocused: Bool = true, cancelFocused: Bool = false, overlap: Bool = false, dropKey: Bool = false, outsideKey: Bool = false, fieldClass: String = "com.android.keyguard.PasswordTextView", fieldText: String? = nil) -> String {
        let text = fieldText ?? String(repeating: "•", count: bullets)
        let field = hyperosNode("pinEntry", fieldClass, bounds: "[200,720][700,820]", password: "true", focused: "true", focusable: "true", text: text)
        func keys(_ digits: [Int]) -> String {
            digits.map { digit in
                let bounds = outsideKey && digit == 1 ? "[0,200][40,240]" : hyperosKeyBounds(digit, overlap: overlap)
                return hyperosNode("key\(digit)", "android.view.ViewGroup", bounds: bounds, clickable: "true", focusable: "true")
            }.joined()
        }
        let present = dropKey ? [0, 1, 2, 3, 4, 5, 6, 7, 8] : Array(0...9)
        let deleteChild = deleteClickable ? hyperosNode("delete_button", "android.widget.ImageView", bounds: "[580,1460][740,1570]", clickable: "true", focusable: "true") : ""
        let delete = hyperosNode("delete_container", "android.widget.FrameLayout", bounds: "[560,1440][760,1590]", clickable: deleteClickable ? "true" : "false", focusable: deleteClickable ? "true" : "false", children: deleteChild)
        let emergency = hyperosNode("emergency_call_button", "android.widget.Button", bounds: "[100,1600][300,1700]", focused: emergencyFocused ? "true" : "false", clickable: "true", focusable: "true")
        let cancel = hyperosNode("cancel_button", "android.widget.TextView", bounds: "[560,1600][760,1700]", focused: cancelFocused ? "true" : "false", clickable: "true", focusable: "true")
        let fade = hyperosNode("keyguard_selector_fade_container", "android.widget.LinearLayout", bounds: "[100,1600][760,1700]", children: emergency + (bullets == 0 ? cancel : ""))
        let rows = hyperosNode("row0", "android.widget.RelativeLayout", bounds: "[100,700][800,860]", children: field)
            + hyperosNode("row1", "android.widget.LinearLayout", bounds: "[100,900][800,1050]", children: keys(present.filter { (1...3).contains($0) }))
            + hyperosNode("row2", "android.widget.LinearLayout", bounds: "[100,1080][800,1230]", children: keys(present.filter { (4...6).contains($0) }))
            + hyperosNode("row3", "android.widget.LinearLayout", bounds: "[100,1260][800,1410]", children: keys(present.filter { (7...9).contains($0) }))
            + hyperosNode("row4", "android.widget.LinearLayout", bounds: "[100,1440][800,1590]", children: keys(present.filter { $0 == 0 }) + delete)
        let container = hyperosNode("pin_container", "android.widget.LinearLayout", bounds: "[100,700][800,1700]", children: rows + fade)
        let face = hyperosNode("miui_keyguard_face_unlock_view", "android.view.ViewGroup", bounds: "[0,40][80,120]", clickable: "true", focusable: "true")
        let header = hyperosNode("fl_header_view", "android.widget.FrameLayout", bounds: "[0,25][900,200]", children: face)
        let pinView = hyperosNode("keyguard_pin_view", "android.widget.LinearLayout", bounds: "[0,0][900,1800]", children: header + container)
        let flipper = hyperosNode("view_flipper", "android.widget.ViewFlipper", bounds: "[0,0][900,1800]", children: pinView)
        let security = hyperosNode("keyguard_security_container", "android.view.ViewGroup", bounds: "[0,0][900,1800]", children: flipper)
        let bouncer = hyperosNode("keyguard_bouncer_container", "android.widget.FrameLayout", bounds: "[0,0][900,1800]", children: security)
        return "<?xml version=\"1.0\"?><hierarchy>" + bouncer + "</hierarchy>"
    }
    let hyperosXML = hyperosFixture()
    let hyperosTarget = pinTarget(xml: hyperosXML, windowText: focus)
    ck(hyperosTarget?.mode == .hyperos && hyperosTarget?.count == 0 && hyperosTarget?.keys.count == 10)
    ck(hyperosTarget?.keys[1]?.center.0 == 200 && hyperosTarget?.keys[1]?.center.1 == 975)
    ck(hyperosTarget?.keys[0]?.center.0 == 430 && hyperosTarget?.keys[0]?.center.1 == 1515)
    var hyperosState = s; hyperosState.target = hyperosTarget
    ck(decision(hyperosState) == "ready")
    // Real HyperOS shaped PINs keep empty accessibility text while the footer switches to delete.
    let shapedNonempty = hyperosXML.replacingOccurrences(of: "id/cancel_button", with: "id/delete_button")
    ck(pinTarget(xml: shapedNonempty, windowText: focus) == nil)
    ck(parseHierarchy(shapedNonempty)?.hyperosFailure == "entered_progress_unavailable")
    for count in 1...16 {
        let parsed = parseHierarchy(shapedNonempty, hyperosProgressCount: count)!
        ck(pinTarget(delegate: parsed, windowText: focus)?.count == count)
    }
    for count in [-1, 0, 17] {
        let parsed = parseHierarchy(shapedNonempty, hyperosProgressCount: count)!
        ck(pinTarget(delegate: parsed, windowText: focus) == nil)
    }
    ck(pinTarget(delegate: parseHierarchy(hyperosXML, hyperosProgressCount: 1)!, windowText: focus) == nil)
    ck(hyperosMaskedProgress("•", observedCount: 2) == nil)
    ck(hyperosMaskedProgress("x", observedCount: 1) == nil)
    ck(hyperosSystemUICodeMatches(hyperosSystemUISHA256 + "  " + hyperosSystemUIPath + "\n"))
    ck(!hyperosSystemUICodeMatches(String(repeating: "0", count: 64) + "  " + hyperosSystemUIPath))
    ck(hyperosProgressHeader("__AU_HYPEROS_V1__ 1 16 0 24", sequence: 1)?.count == 16)
    for line in ["__AU_HYPEROS_V1__ 2 1 0 24", "__AU_HYPEROS_V1__ 1 17 0 24", "__AU_HYPEROS_V1__ 1 1 0 262145", "__AU_HYPEROS_V1__ 1 1 3 24", "__AU_HYPEROS_V1__ 1 01 0 24", "__AU_HYPEROS_V1__ 1 1 0 24 extra", "__AU_FLYME_V1__ 1 1 0 24"] {
        ck(hyperosProgressHeader(line, sequence: 1) == nil)
    }
    ck(pinTarget(xml: hyperosXML.replacingOccurrences(of: "id/cancel_button", with: "id/unknown_footer"), windowText: focus) == nil)
    let duplicateCancel = hyperosNode("cancel_button", "android.widget.TextView", bounds: "[560,1600][760,1700]", clickable: "true", focusable: "true")
    let duplicatedFooter = hyperosXML.replacingOccurrences(of: duplicateCancel, with: duplicateCancel + duplicateCancel)
    ck(pinTarget(xml: duplicatedFooter, windowText: focus) == nil)
    ck(pinTarget(xml: shapedNonempty.replacingOccurrences(of: "id/delete_button", with: "id/cancel_button"), windowText: focus)?.count == 0)
    let invalidFooter = hyperosXML.replacingOccurrences(of: "id/cancel_button\" class=\"android.widget.TextView", with: "id/cancel_button\" class=\"android.widget.ImageView")
    ck(pinTarget(xml: invalidFooter, windowText: focus) == nil)
    ck(pinTarget(xml: hyperosFixture(emergencyFocused: false), windowText: focus)?.count == 0)
    let hyperosMasked = pinTarget(xml: hyperosFixture(bullets: 1, deleteClickable: true), windowText: focus)
    ck(hyperosMasked?.mode == .hyperos && hyperosMasked?.count == 1)
    var hyperosFilled = hyperosState; hyperosFilled.target = hyperosMasked
    ck(decision(hyperosFilled) == "pin_field_not_empty")
    ck(hyperosTarget?.placeholder == uiBounds(hyperosTarget!.field))
    ck(activityEligible(hyperosState, authorized: true))
    ck(!activityEligible(hyperosState, authorized: false))
    ck(!activityEligible(hyperosFilled, authorized: true))
    var hyperosProof = hyperosState; hyperosProof.serial = "synthetic"
    hyperosProof.focusResult = "focus_identity_verified"; hyperosProof.focusSource = "displays"; hyperosProof.focusDisplayID = 0
    hyperosProof.hierarchyResult = "hierarchy_xml_parsed"; hyperosProof.hierarchyStdoutEmpty = false
    hyperosProof.postUIStateChecked = true; hyperosProof.observedAt = 100; hyperosProof.postUIVerifiedAt = 101
    ck(immediateTrustedPinActivityObservation(hyperosProof, serial: "synthetic", authorized: true, now: 101.1))
    ck(freshHyperOSInputProof(hyperosProof, expected: 0, now: 101.1))
    ck(!freshHyperOSInputProof(hyperosProof, expected: 1, now: 101.1))
    ck(!freshHyperOSInputProof(hyperosProof, expected: 0, now: 102.001))
    ck(!immediateTrustedPinActivityObservation(hyperosProof, serial: "synthetic", authorized: true, now: 102.001))
    ck(!immediateTrustedPinActivityObservation(hyperosProof, serial: "other", authorized: true, now: 101.1))
    var invalidHyperosProof = hyperosProof; invalidHyperosProof.postUIStateChecked = false
    ck(!immediateTrustedPinActivityObservation(invalidHyperosProof, serial: "synthetic", authorized: true, now: 101.1))
    invalidHyperosProof = hyperosProof; invalidHyperosProof.target?.placeholder = nil
    ck(!immediateTrustedPinActivityObservation(invalidHyperosProof, serial: "synthetic", authorized: true, now: 101.1))
    invalidHyperosProof = hyperosProof; invalidHyperosProof.target?.placeholder = uiBounds("[0,0][900,1800]")
    ck(!immediateTrustedPinActivityObservation(invalidHyperosProof, serial: "synthetic", authorized: true, now: 101.1))
    invalidHyperosProof = hyperosProof; invalidHyperosProof.target?.keys[1] = hyperosTarget!.placeholder
    ck(!immediateTrustedPinActivityObservation(invalidHyperosProof, serial: "synthetic", authorized: true, now: 101.1))
    invalidHyperosProof = hyperosProof; invalidHyperosProof.focusResult = "focus_unverified"
    ck(!immediateTrustedPinActivityObservation(invalidHyperosProof, serial: "synthetic", authorized: true, now: 101.1))
    for badXML in [hyperosFixture(deleteClickable: true), hyperosFixture(bullets: 1), hyperosFixture(bullets: 17, deleteClickable: true), hyperosFixture(fieldText: "x"), hyperosFixture(deleteClickable: true, fieldText: "•1"), hyperosFixture(cancelFocused: true), hyperosFixture(overlap: true), hyperosFixture(dropKey: true), hyperosFixture(outsideKey: true), hyperosFixture(fieldClass: "android.widget.EditText")] {
        ck(pinTarget(xml: badXML, windowText: focus) == nil)
    }
    ck(pinTarget(xml: hyperosXML.replacingOccurrences(of: "id/emergency_call_button", with: "id/unknown_button"), windowText: focus) == nil)
    ck(pinTarget(xml: hyperosXML.replacingOccurrences(of: "id/keyguard_pin_view", with: "id/unknown_pin_view"), windowText: focus) == nil)
    ck(pinTarget(xml: hyperosXML.replacingOccurrences(of: "package=\"com.android.systemui\"", with: "package=\"example.other\""), windowText: focus) == nil)
    var hyperosActions: [Int] = []
    ck(drivePIN(Data("0123".utf8), initial: hyperosState, observe: { final in
        var next = hyperosState
        if final { next.state = .unlocked; next.target = nil }
        else { next.target = pinTarget(xml: hyperosFixture(bullets: hyperosActions.count, deleteClickable: hyperosActions.count > 0), windowText: focus) }
        return next
    }, send: { key in ck(key != 66); hyperosActions.append(key); return true }) == .submitted)
    ck(hyperosActions == [7, 8, 9, 10])
    hyperosActions = []
    ck(drivePIN(Data("0123".utf8), initial: hyperosState, observe: { _ in hyperosState }, send: { key in hyperosActions.append(key); return true }) == .partial && hyperosActions == [7])
    ck(drivePIN(Data("012".utf8), initial: hyperosState, observe: { _ in fatalError("short hyperos pin") }, send: { _ in fatalError("short hyperos pin") }) == .refused)
    ck(drivePIN(Data(repeating: 48, count: 17), initial: hyperosState, observe: { _ in fatalError("long hyperos pin") }, send: { _ in fatalError("long hyperos pin") }) == .refused)
    hyperosActions = []
    let aospBesideUnrelatedKey = xml.replacingOccurrences(of: "</hierarchy>", with: hyperosNode("key1", "android.view.ViewGroup", bounds: "[4,5][6,7]", clickable: "true", focusable: "true") + hyperosNode("delete_container", "android.widget.FrameLayout", bounds: "[8,9][10,11]") + "</hierarchy>")
    ck(pinTarget(xml: aospBesideUnrelatedKey, windowText: focus)?.mode == .aosp)
    ck(drivePIN(Data("012345".utf8), initial: hyperosState, observe: { final in
        var next = hyperosState
        if final { next.state = .unlocked; next.target = nil }
        else { next.target = pinTarget(xml: hyperosFixture(bullets: hyperosActions.count, deleteClickable: hyperosActions.count > 0), windowText: focus) }
        return next
    }, send: { key in ck(key != 66); hyperosActions.append(key); return true }) == .submitted && hyperosActions == [7, 8, 9, 10, 11, 12])
    print("\(n) synthetic checks passed; fixture callbacks only; no real ADB/input/Keychain")
 }
}
