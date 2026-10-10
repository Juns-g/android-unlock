import Foundation
import Darwin
let args = Array(CommandLine.arguments.dropFirst())
if args == ["help"] || args == ["--help"] {
    print("""
android-unlock help
android-unlock devices
android-unlock status --serial SERIAL
android-unlock preflight --serial SERIAL
android-unlock unlock --dry-run --serial SERIAL
android-unlock unlock --authorize --serial SERIAL
android-unlock setup --local-user --serial SERIAL
android-unlock authorize-existing --local-user --serial SERIAL

Authorized unlock: one bounded wake-only event and verified PIN-page presentation.
Strict numeric PIN; Vivo six-slot input verified with temporary source.
Production Keychain permission still requires real verification.
Read-only commands never query Keychain, wake, swipe, input, or persist UI hierarchy.
setup: masked local UI, stable installed app only; numeric PIN, primary Android user 0.
authorize-existing: USER ONLY; interactive read then one same-process noninteractive verification.
Success never proves persistent or next-process permission; unlocked secure phone required.
No secret CLI/env/file arguments; existing authorized ADB only. No server setup/restart.
Exit: 0 observed/ready/confirmed; 2 blocked; 3 attempted unconfirmed; 64 usage.
"""); exit(0)
}
let command = args.first ?? ""
var s = Snapshot()
var credential = "not_queried"
var credentialDiagnostics: [CredentialMetadata] = []
var authorizationProofScope = "not_verified"
var submitted = false
var activityAttempted = false
var activitySucceeded = false
var preparation = Preparation(snapshot: Snapshot())
var listed: [Device]? = nil
func emit(_ result: String, code: Int32, count: Int? = nil) -> Never {
    var r: [String: Any] = ["command": ["devices", "status", "preflight", "unlock", "setup", "authorize-existing"].contains(command) ? command : "invalid",
        "result": result, "code": code, "lockState": s.state.rawValue, "online": s.online,
        "awake": s.awake, "screenKnown": s.screenKnown, "secure": s.secure,
        "focusResult": s.focusResult, "focusSource": s.focusSource,
        "hierarchyResult": s.hierarchyResult, "hierarchyStdoutEmpty": s.hierarchyStdoutEmpty, "hierarchyStderrPresent": s.hierarchyStderrPresent,
        "preparationAttempted": preparation.attempted, "preparationResult": preparation.result,
        "activityAttempted": activityAttempted, "activitySucceeded": activitySucceeded,
        "wakeAttempted": preparation.wakeAttempted, "presentationAttempted": preparation.presentationAttempted,
        "wakePlanned": decision(s) == "preparation_needed_wake", "pinPagePresentationPlanned": decision(s) == "preparation_needed_pin_page", "credential": credential, "submitted": submitted,
        "pinPathImplemented": true, "inputSupported": decision(s) == "ready", "securePinTargetVerified": s.target != nil]
    if !credentialDiagnostics.isEmpty { r["credentialDiagnostics"] = credentialDiagnostics.map { $0.json } }
    if command == "authorize-existing" {
        r["proofScope"] = authorizationProofScope; r["persistentPermissionVerified"] = false
    }
    if let display = s.focusDisplayID { r["focusDisplayId"] = display }
    if let user = s.user { r["androidUser"] = user }
    if let count { r["deviceCount"] = count }
    if let listed { r["devices"] = listed.map { ["serial": $0.serial, "state": $0.state] } }
    if let d = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]), let t = String(data: d, encoding: .utf8) { print(t) }
    exit(code)
}
if args == ["devices"] {
    guard let list = inventory() else { emit("adb_inventory_unverified", code: 2) }
    listed = list
    emit(list.isEmpty ? "no_devices" : "devices_present_use_explicit_serial", code: 0, count: list.count)
}
let validRead = args.count == 3 && ["status", "preflight"].contains(command) && args[1] == "--serial"
let validAction = args.count == 4 && ((command == "unlock" && ["--dry-run", "--authorize"].contains(args[1])) ||
    (["setup", "authorize-existing"].contains(command) && args[1] == "--local-user")) && args[2] == "--serial"
guard validRead || validAction, let serial = args.last, validSerial(serial) else { emit("invalid_arguments_use_help", code: 64) }
s = snapshot(serial, queryTarget: command != "authorize-existing")
if command == "status" { emit(s.reason, code: s.reason == "observed" ? 0 : 2) }
if command == "authorize-existing" {
    guard let fd = acquireLock() else { emit("busy_or_lock_unavailable", code: 2) }; defer { close(fd) }
    let r = authorizeExisting(s)
    credentialDiagnostics = r.diagnostics; authorizationProofScope = r.proofScope
    credential = r.result == "credential_authorized" ? "own_existing_pin_same_process_verified" :
        r.result == "credential_authorized_noninteractive_blocked" ? "own_existing_pin_interactive_only" : "authorization_blocked"
    emit(r.result, code: r.result == "credential_authorized" ? 0 : 2)
}
if command == "setup" {
    guard let fd = acquireLock() else { emit("busy_or_lock_unavailable", code: 2) }; defer { close(fd) }
    let r = setup(s); credential = r == "pin_saved" ? "own_pin_saved" : "setup_not_saved"; emit(r, code: r == "pin_saved" ? 0 : 2)
}
if args.contains("--authorize") {
    guard let fd = acquireLock() else { emit("busy_or_lock_unavailable", code: 2) }; defer { close(fd) }
    guard Bundle.main.executableURL?.resolvingSymlinksInPath().path == stablePath else { emit("install_at_stable_path_first", code: 2) }
    preparation = prepareNative(s); s = preparation.snapshot
    guard preparation.result == "ready" else {
        emit(preparation.result, code: preparation.result == "already_unlocked" ? 0 : preparation.attempted ? 3 : 2)
    }
    let initial = s; var pin: Data?; var before = initial; var firstCheck = true
    let outcome = attempt(initial, authorized: true, recheck: {
        if firstCheck {
            firstCheck = false; before = snapshot(serial, reusingUI: initial); return before
        }
        if activityEligible(before, authorized: true) {
            activityAttempted = true; activitySucceeded = pinActivity(before, authorized: true)
            if !activitySucceeded { var failed = before; failed.reason = "activity_unconfirmed_no_retry"; return failed }
        }
        before = snapshot(serial); return before
    }, read: {
        credential = "own_pin_requested_no_interaction"
        var read = fetchPIN(serial); credentialDiagnostics = [read.metadata]; pin = read.pin; read.pin = nil
        return pin != nil
    }, submit: { guard let pin else { return .refused }; return submitPIN(pin, initial: before) }, confirm: {
        s = confirmUnlock(initial); return s
    })
    if pin != nil { pin!.resetBytes(in: 0..<pin!.count); pin = nil }
    submitted = outcome.1
    emit(outcome.0, code: ["already_unlocked", "unlocked_confirmed"].contains(outcome.0) ? 0 : submitted ? 3 : 2)
}
let r = decision(s); emit(r, code: ["already_unlocked", "ready"].contains(r) ? 0 : 2)
