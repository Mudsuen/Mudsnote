import Darwin
import Foundation

/// Owns one already-configured child. It never discovers a runtime or reads
/// credentials, so lifecycle fixtures can use this same boundary safely.
final class CodexProcessExecution: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private let terminationGrace: Duration
    private let timeout: Duration?
    private var cancelled = false
    private var timedOut = false
    private var started = false
    private var finished = false
    private var continuation: CheckedContinuation<Int32, Error>?
    private var killTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        process: Process,
        terminationGrace: Duration = .seconds(1),
        timeout: Duration? = nil
    ) {
        self.process = process
        self.terminationGrace = terminationGrace
        self.timeout = timeout
    }

    func run() async throws -> Int32 {
        let status = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { launch($0) }
        } onCancel: { self.cancel(dueToTimeout: false) }
        try Task.checkCancellation()
        return status
    }

    private func launch(_ continuation: CheckedContinuation<Int32, Error>) {
        lock.lock()
        if cancelled {
            let wasTimeout = timedOut
            lock.unlock()
            if wasTimeout {
                continuation.resume(throwing: AIError.requestFailed("Codex 执行超时，已终止。"))
            } else {
                continuation.resume(throwing: CancellationError())
            }
            return
        }
        self.continuation = continuation
        process.terminationHandler = { [weak self] _ in self?.didExit() }
        do {
            // Cancellation and launch share the same owner lock, closing the
            // check-before-launch race without a blocking input pipe.
            try process.run()
            started = true
            if let timeout {
                timeoutTask = Task.detached { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.cancel(dueToTimeout: true)
                }
            }
            lock.unlock()
        } catch {
            finished = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(throwing: error)
        }
    }

    private func cancel(dueToTimeout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if dueToTimeout {
            timedOut = true
        }
        guard started, !finished, killTask == nil else { return }
        let pid = process.processIdentifier
        if process.isRunning {
            signalProcessAndGroup(pid: pid, signal: SIGTERM)
        }
        let grace = terminationGrace
        killTask = Task.detached { [weak self] in
            do { try await Task.sleep(for: grace) } catch { return }
            self?.killIfStillOwned(pid)
        }
    }

    private func killIfStillOwned(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard started, !finished, process.isRunning, process.processIdentifier == pid else { return }
        signalProcessAndGroup(pid: pid, signal: SIGKILL)
    }

    private func signalProcessAndGroup(pid: Int32, signal: Int32) {
        guard pid > 0 else { return }
        let childPGID = getpgid(pid)
        let ownPGID = getpgrp()
        if childPGID > 0, childPGID != ownPGID {
            _ = kill(-childPGID, signal)
        }
        _ = kill(pid, signal)
    }

    private func didExit() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        killTask?.cancel()
        killTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        let wasCancelled = cancelled
        let wasTimeout = timedOut
        let status = process.terminationStatus
        lock.unlock()
        if wasTimeout {
            continuation?.resume(throwing: AIError.requestFailed("Codex 执行超时，已终止。"))
        } else if wasCancelled {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(returning: status)
        }
    }

    static func runPrepared(
        _ process: Process,
        prompt: String,
        workingDirectory: URL,
        terminationGrace: Duration = .seconds(1),
        timeout: Duration? = nil
    ) async throws -> Int32 {
        try Task.checkCancellation()
        let inputURL = workingDirectory.appendingPathComponent("mudsnote-input-\(UUID().uuidString).txt")
        try Data(prompt.utf8).write(to: inputURL, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: inputURL) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inputURL.path)
        let input = try FileHandle(forReadingFrom: inputURL)
        defer { try? input.close() }
        process.standardInput = input
        let execution = CodexProcessExecution(
            process: process,
            terminationGrace: terminationGrace,
            timeout: timeout
        )
        return try await execution.run()
    }
}
