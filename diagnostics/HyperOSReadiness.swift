import Foundation
import Darwin

// No credential access or digit dispatch. Run from a temporary diagnostic App containing the pinned collector.
@main struct HyperOSReadiness {
    static func main() {
        guard CommandLine.arguments.count == 2, let fd = acquireLock() else { print("diagnostic_unavailable"); return }
        defer { close(fd) }
        let serial = CommandLine.arguments[1]
        let initial = snapshot(serial)
        guard initial.state == .locked else { print("locked_start_required"); return }
        let prepared = prepareNative(initial)
        print("preparation=" + prepared.result)
        guard prepared.result == "ready", prepared.snapshot.target?.mode == .hyperos else { return }
        let before = snapshot(serial, reusingUI: prepared.snapshot)
        guard before.target == prepared.snapshot.target, activityEligible(before, authorized: true), pinActivity(before, authorized: true) else {
            print("empty_field_activity_unverified"); return
        }
        let inputReady = snapshot(serial)
        guard decision(inputReady) == "ready", inputReady.target == before.target else { print("input_readiness_changed"); return }
        guard let progress = HyperOSNativeProgress(serial, limit: 4) else { print("observer_bind_failed"); return }
        defer { progress.stop() }
        let observed = snapshot(serial, hyperosProgress: progress)
        let valid = consistent(inputReady, observed) && observed.target == inputReady.target &&
            freshHyperOSInputProof(observed, expected: 0, now: ProcessInfo.processInfo.systemUptime)
        print("observer_empty_proof=\(valid);result=\(progress.result);hierarchy=\(observed.hierarchyResult);reason=\(observed.reason)")
        guard valid else { return }
        // Deliberately request one unobserved append without arming or sending any input.
        progress.expected = 1
        let absent = progress.snapshotOutput()
        print("missing_append_rejected=\(!absent.ok && progress.result == "hyperos_progress_missing_ack");result=\(progress.result)")
        print("credential=not_queried;digit_actions=0")
    }
}
