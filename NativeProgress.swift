import Foundation
import Darwin

// One bounded non-PTY client owns the ONLY UiAutomation connection during Flyme input.
final class FlymeNativeProgress {
    let serial: String
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var sequence = 0
    private let deadline = ProcessInfo.processInfo.systemUptime + 80
    var expected = 0 // Expected next observed count; never evidence that input was accepted.
    private(set) var observedCount: Int? = nil
    var result = "flyme_progress_not_started"
    init?(_ serial: String) {
        guard validSerial(serial), trustedADB(), deviceDecision(inventory(), serial: serial) == "online" else { return nil }
        self.serial = serial
        let pipeline = "'/system/bin/uiautomator runtest " + collectorDevicePath + " -c page.juns.androidunlock.FlymeProgressSession#testProgress -s | /system/bin/cat'"
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-H", "127.0.0.1", "-P", "5037", "-s", serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "80", "/system/bin/sh", "-c", pipeline]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LC_ALL": "C"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        input.fileHandleForReading.closeFile(); output.fileHandleForWriting.closeFile()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }
    private func request(_ command: String, count: Int, xml: Bool) -> Data? {
        observedCount = nil
        guard process.isRunning, ProcessInfo.processInfo.systemUptime < deadline, sequence < 20 else { result = "flyme_progress_process_or_deadline"; return nil }
        do { try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8)) }
        catch { result = "flyme_progress_pipe_failed"; return nil }
        sequence += 1
        let until = min(deadline, ProcessInfo.processInfo.systemUptime + 3)
        let marker = Data("__AU_FLYME_V1__ ".utf8)
        while ProcessInfo.processInfo.systemUptime < until {
            if let start = buffer.range(of: marker) {
                guard start.lowerBound <= 16384 else { break }
                if let newline = buffer[start.lowerBound...].firstIndex(of: 10) {
                    guard newline - start.lowerBound <= 100,
                          let line = String(data: buffer[start.lowerBound..<newline], encoding: .utf8),
                          let header = progressHeader(line, sequence: sequence) else { result = "flyme_progress_protocol_invalid"; return nil }
                    if header.error != 0 {
                        result = [1: "flyme_progress_context_or_reset", 2: "flyme_progress_source_unverified", 3: "flyme_progress_duplicate_or_unexpected", 4: "flyme_progress_missing_ack", 5: "flyme_progress_field_changed", 6: "flyme_progress_command_invalid", 7: "flyme_progress_limit_or_runtime"][header.error] ?? "flyme_progress_protocol_invalid"
                        return nil
                    }
                    guard header.count == count, xml ? header.length > 0 : header.length == 0 else { result = "flyme_progress_count_or_frame_mismatch"; return nil }
                    let end = newline + 1 + header.length
                    if buffer.count >= end {
                        let data = Data(buffer[(newline + 1)..<end])
                        buffer.resetBytes(in: 0..<end); buffer.removeSubrange(0..<end)
                        result = "flyme_progress_source_ack_verified"
                        observedCount = header.count
                        return data
                    }
                }
            }
            guard buffer.count <= 300000 else { break }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
            if n > 0 { buffer.append(contentsOf: bytes.prefix(n)); _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
            else if n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) { break }
            else { Thread.sleep(forTimeInterval: 0.005) }
        }
        result = "flyme_progress_frame_missing_or_late"; return nil
    }
    func snapshotOutput() -> Output {
        guard let data = request("SNAP \(expected)", count: expected, xml: true) else { return Output(data: Data(), ok: false) }
        return Output(data: data, ok: true)
    }
    func arm() -> Bool { request("ARM \(expected)", count: expected, xml: false) != nil }
    func finalAcknowledged() -> Bool { request("ACK 4", count: 4, xml: false) != nil }
    func stop() {
        if process.isRunning { try? input.fileHandleForWriting.write(contentsOf: Data("QUIT\n".utf8)) }
        input.fileHandleForWriting.closeFile()
        let until = ProcessInfo.processInfo.systemUptime + 4
        while process.isRunning && ProcessInfo.processInfo.systemUptime < until {
            var discarded = [UInt8](repeating: 0, count: 8192)
            _ = Darwin.read(output.fileHandleForReading.fileDescriptor, &discarded, discarded.count)
            _ = discarded.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            Thread.sleep(forTimeInterval: 0.005)
        }
        if process.isRunning { process.terminate() }
        let killed = ProcessInfo.processInfo.systemUptime + 0.15
        while process.isRunning && ProcessInfo.processInfo.systemUptime < killed { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit(); output.fileHandleForReading.closeFile()
        buffer.resetBytes(in: 0..<buffer.count); buffer.removeAll()
    }
}

func submitFlymeProgressPIN(_ pin: Data, initial: Snapshot, report: ((Snapshot, Int, Int) -> Void)?) -> InputResult {
    guard validPIN(pin), pin.count == 4, decision(initial) == "ready", initial.target?.mode == .flymeFour,
          let progress = FlymeNativeProgress(initial.serial) else { return .refused }
    defer { progress.stop() }
    var last = snapshot(initial.serial, progress: progress)
    last.progressPhase = "pre_input_full"
    guard consistent(initial, last), last.target == initial.target, decision(last) == "ready" else { report?(last, 0, 0); return .refused }
    var first = true; var actions = 0; var succeeded = 0
    let outcome = drivePIN(pin, initial: initial, observe: { final in
        if final {
            guard progress.finalAcknowledged() else { var failed = last; failed.reason = progress.result; report?(failed, actions, succeeded); return failed }
            last = confirmUnlock(initial)
            last.progressPhase = "final_ack_and_confirmation"
        } else if first { first = false }
        else { last = snapshot(initial.serial, progress: progress); last.progressPhase = "after_input_full" }
        if !final && !freshFlymeInputProof(last, expected: progress.expected, now: ProcessInfo.processInfo.systemUptime) {
            last.reason = "flyme_progress_fresh_proof_unverified"
        }
        report?(last, actions, succeeded); return last
    }, send: { key in
        guard (7...16).contains(key), freshFlymeInputProof(last, expected: progress.expected, now: ProcessInfo.processInfo.systemUptime),
              let rect = last.target?.keys[key - 7], progress.arm(),
              freshFlymeInputProof(last, expected: progress.expected, now: ProcessInfo.processInfo.systemUptime) else { return false }
        let point = rect.center
        var payload = Data("exec /system/bin/input tap \(point.0) \(point.1)\n".utf8)
        defer { payload.resetBytes(in: 0..<payload.count) }
        actions += 1
        let outcome = runADB(["-s", initial.serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/sh"], timeout: 4, confidential: payload)
        if outcome.ok { succeeded += 1; progress.expected += 1 }
        var sampledBeforeAction = last; sampledBeforeAction.progressPhase = "dispatch_adb_result_pre_input_sample"
        report?(sampledBeforeAction, actions, succeeded)
        return outcome.ok
    })
    return actions == 0 && outcome == .partial ? .refused : outcome
}

// One bounded non-PTY client owns the ONLY UiAutomation connection during HyperOS input.
final class HyperOSNativeProgress {
    let serial: String
    let limit: Int
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var sequence = 0
    private let deadline = ProcessInfo.processInfo.systemUptime + 80
    var expected = 0 // Expected next observed count; never evidence that input was accepted.
    private(set) var observedCount: Int? = nil
    var result = "hyperos_progress_not_started"
    init?(_ serial: String, limit: Int) {
        guard (4...16).contains(limit), validSerial(serial), trustedADB(), deviceDecision(inventory(), serial: serial) == "online" else { return nil }
        self.serial = serial; self.limit = limit
        let pipeline = "'/system/bin/uiautomator runtest " + collectorDevicePath + " -c page.juns.androidunlock.HyperOSProgressSession#testProgress -s | /system/bin/cat'"
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-H", "127.0.0.1", "-P", "5037", "-s", serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "80", "/system/bin/sh", "-c", pipeline]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LC_ALL": "C"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        input.fileHandleForReading.closeFile(); output.fileHandleForWriting.closeFile()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        guard request("BEGIN \(limit)", count: 0, xml: false) != nil else { stop(); return nil }
    }
    private func request(_ command: String, count: Int, xml: Bool) -> Data? {
        observedCount = nil
        guard process.isRunning, ProcessInfo.processInfo.systemUptime < deadline, sequence < 40 else { result = "hyperos_progress_process_or_deadline"; return nil }
        do { try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8)) }
        catch { result = "hyperos_progress_pipe_failed"; return nil }
        sequence += 1
        let until = min(deadline, ProcessInfo.processInfo.systemUptime + 3)
        let marker = Data("__AU_HYPEROS_V1__ ".utf8)
        while ProcessInfo.processInfo.systemUptime < until {
            if let start = buffer.range(of: marker) {
                guard start.lowerBound <= 16384 else { break }
                if let newline = buffer[start.lowerBound...].firstIndex(of: 10) {
                    guard newline - start.lowerBound <= 100,
                          let line = String(data: buffer[start.lowerBound..<newline], encoding: .utf8),
                          let header = hyperosProgressHeader(line, sequence: sequence) else { result = "hyperos_progress_protocol_invalid"; return nil }
                    if header.error != 0 {
                        result = [1: "hyperos_progress_context_or_reset", 2: "hyperos_progress_source_unverified", 3: "hyperos_progress_duplicate_or_unexpected", 4: "hyperos_progress_missing_ack", 5: "hyperos_progress_field_changed", 6: "hyperos_progress_command_invalid", 7: "hyperos_progress_limit_or_runtime"][header.error] ?? "hyperos_progress_protocol_invalid"
                        return nil
                    }
                    guard header.count == count, xml ? header.length > 0 : header.length == 0 else { result = "hyperos_progress_count_or_frame_mismatch"; return nil }
                    let end = newline + 1 + header.length
                    if buffer.count >= end {
                        let data = Data(buffer[(newline + 1)..<end])
                        buffer.resetBytes(in: 0..<end); buffer.removeSubrange(0..<end)
                        result = "hyperos_progress_source_ack_verified"
                        observedCount = header.count
                        return data
                    }
                }
            }
            guard buffer.count <= 300000 else { break }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
            if n > 0 { buffer.append(contentsOf: bytes.prefix(n)); _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
            else if n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) { break }
            else { Thread.sleep(forTimeInterval: 0.005) }
        }
        result = "hyperos_progress_frame_missing_or_late"; return nil
    }
    func snapshotOutput() -> Output {
        guard let data = request("SNAP \(expected)", count: expected, xml: true) else { return Output(data: Data(), ok: false) }
        return Output(data: data, ok: true)
    }
    func arm() -> Bool { request("ARM \(expected)", count: expected, xml: false) != nil }
    func finalAcknowledged() -> Bool { request("ACK \(limit)", count: limit, xml: false) != nil }
    func stop() {
        if process.isRunning { try? input.fileHandleForWriting.write(contentsOf: Data("QUIT\n".utf8)) }
        input.fileHandleForWriting.closeFile()
        let until = ProcessInfo.processInfo.systemUptime + 4
        while process.isRunning && ProcessInfo.processInfo.systemUptime < until {
            var discarded = [UInt8](repeating: 0, count: 8192)
            _ = Darwin.read(output.fileHandleForReading.fileDescriptor, &discarded, discarded.count)
            _ = discarded.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            Thread.sleep(forTimeInterval: 0.005)
        }
        if process.isRunning { process.terminate() }
        let killed = ProcessInfo.processInfo.systemUptime + 0.15
        while process.isRunning && ProcessInfo.processInfo.systemUptime < killed { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit(); output.fileHandleForReading.closeFile()
        buffer.resetBytes(in: 0..<buffer.count); buffer.removeAll()
    }
}

func submitHyperOSProgressPIN(_ pin: Data, initial: Snapshot, report: ((Snapshot, Int, Int) -> Void)?) -> InputResult {
    guard validPIN(pin), (4...16).contains(pin.count), decision(initial) == "ready", initial.target?.mode == .hyperos,
          let progress = HyperOSNativeProgress(initial.serial, limit: pin.count) else { return .refused }
    defer { progress.stop() }
    var last = snapshot(initial.serial, hyperosProgress: progress)
    last.progressPhase = "pre_input_full"
    guard consistent(initial, last), last.target == initial.target, decision(last) == "ready" else { report?(last, 0, 0); return .refused }
    var first = true; var actions = 0; var succeeded = 0
    let outcome = drivePIN(pin, initial: initial, observe: { final in
        if final {
            guard progress.finalAcknowledged() else { var failed = last; failed.reason = progress.result; report?(failed, actions, succeeded); return failed }
            last = confirmUnlock(initial)
            last.progressPhase = "final_ack_and_confirmation"
        } else if first { first = false }
        else { last = snapshot(initial.serial, hyperosProgress: progress); last.progressPhase = "after_input_full" }
        if !final && !freshHyperOSInputProof(last, expected: progress.expected, now: ProcessInfo.processInfo.systemUptime) {
            last.reason = "hyperos_progress_fresh_proof_unverified"
        }
        report?(last, actions, succeeded); return last
    }, send: { key in
        guard (7...16).contains(key), freshHyperOSInputProof(last, expected: progress.expected, now: ProcessInfo.processInfo.systemUptime),
              last.target?.keys[key - 7] != nil, progress.arm(),
              freshHyperOSInputProof(last, expected: progress.expected, now: ProcessInfo.processInfo.systemUptime) else { return false }
        // The pinned OEM onKeyDown maps these standard digit keys to its own bound keypad buttons.
        // Keep the full keypad proof and require the same source-bound append after every action.
        var payload = Data("exec /system/bin/input keyevent \(key)\n".utf8)
        defer { payload.resetBytes(in: 0..<payload.count) }
        actions += 1
        let outcome = runADB(["-s", initial.serial, "shell", "-T", "-e", "none", "toybox", "timeout", "-s", "KILL", "2", "/system/bin/sh"], timeout: 4, confidential: payload)
        if outcome.ok { succeeded += 1; progress.expected += 1 }
        var sampledBeforeAction = last; sampledBeforeAction.progressPhase = "dispatch_adb_result_pre_input_sample"
        report?(sampledBeforeAction, actions, succeeded)
        return outcome.ok
    })
    return actions == 0 && outcome == .partial ? .refused : outcome
}
