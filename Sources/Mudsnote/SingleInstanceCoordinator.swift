import AppKit
import CryptoKit
import Darwin
import Foundation

/// Acquired before AppController creates stores or registers global shortcuts.
/// The kernel releases the lock on exit; the inode must never be unlinked.
final class InstanceLease {
    let directory: URL
    private let descriptor: Int32
    let isOwner: Bool

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        descriptor = open(directory.appendingPathComponent("owner.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            isOwner = true
        } else if errno == EWOULDBLOCK {
            isOwner = false
        } else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(descriptor)
            throw POSIXError(code)
        }
    }

    deinit { close(descriptor) }
}

struct InstanceRequest: Codable {
    var arguments: [String]
    var files: [String]
    var createdAt = Date()
}

@MainActor
final class SingleInstanceCoordinator: NSObject, NSApplicationDelegate {
    let lease: InstanceLease
    let isFixture: Bool
    private let arguments: [String]
    private let legacyApplication: NSRunningApplication?
    private var files: [String] = []
    private var requestURL: URL?
    private var timer: Timer?
    private var deadline = Date.distantFuture

    var isPrimary: Bool { lease.isOwner && legacyApplication == nil }

    static func value(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count,
              !arguments[index + 1].hasPrefix("--") else { return nil }
        return arguments[index + 1]
    }

    static func coordinationDirectory(arguments: [String]) throws -> URL {
        let fixtureFlags = ["--visual-qa-notes-dir", "--visual-qa-defaults-suite", "--visual-qa-app-support-dir"]
        if fixtureFlags.contains(where: arguments.contains) {
            // A partial fixture must not accidentally use personal preferences or support data.
            guard let notes = value(fixtureFlags[0], in: arguments),
                  let suite = value(fixtureFlags[1], in: arguments), !suite.isEmpty,
                  let support = value(fixtureFlags[2], in: arguments),
                  notes.hasPrefix("/"), support.hasPrefix("/") else {
                throw NSError(domain: "Mudsnote.Instance", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Visual QA requires notes, defaults suite and app support directories."])
            }
            let identity = URL(fileURLWithPath: notes).resolvingSymlinksInPath().standardizedFileURL.path
            let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            return FileManager.default.temporaryDirectory.appendingPathComponent("mudsnote-instance-" + hash)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mudsnote/Instance")
    }

    init(arguments: [String]) throws {
        self.arguments = arguments
        isFixture = arguments.contains("--visual-qa-notes-dir")
        lease = try InstanceLease(directory: Self.coordinationDirectory(arguments: arguments))
        // Old builds do not participate in the lock. Yield to them without quitting
        // or replacing their potentially unsaved windows. Fixture apps are separate.
        legacyApplication = lease.isOwner && !isFixture ? Self.existingLegacyApplication() : nil
        super.init()
    }

    private static func existingLegacyApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex.mudsnote")
            .filter { app in
                guard app.processIdentifier != getpid(), !app.isTerminated else { return false }
                return app.bundleURL.flatMap { Bundle(url: $0) }?.object(forInfoDictionaryKey: "MudsnoteInstanceProtocol") as? Int != 1
            }
            .sorted { $0.processIdentifier < $1.processIdentifier }
            .first { app in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/ps")
                process.arguments = ["-p", String(app.processIdentifier), "-o", "command="]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { return true }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return !String(decoding: data, as: UTF8.self).contains("--visual-qa-notes-dir")
            }
    }

    func startReceiving(_ receive: @escaping @MainActor (InstanceRequest) -> Bool) {
        precondition(isPrimary)
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let entries = (try? FileManager.default.contentsOfDirectory(at: self.lease.directory,
                    includingPropertiesForKeys: nil)) ?? []
                for url in entries.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    guard let data = try? Data(contentsOf: url),
                          let request = try? JSONDecoder().decode(InstanceRequest.self, from: data) else { continue }
                    // Never replay abandoned requests on a later manual launch.
                    if Date().timeIntervalSince(request.createdAt) > 30 || receive(request) {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }

    func runSecondary(application: NSApplication) -> Never {
        application.setActivationPolicy(.accessory)
        application.delegate = self
        application.run()
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch Services delivers document Apple events during startup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            forward(arguments: arguments, files: files)
            files.removeAll()
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        files.append(contentsOf: filenames)
        sender.reply(toOpenOrPrint: .success)
    }

    private func forward(arguments: [String], files: [String]) {
        if let legacyApplication, let bundleURL = legacyApplication.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { _, error in
                DispatchQueue.main.async {
                    if let error { FileHandle.standardError.write(Data("Mudsnote handoff failed: \(error)\n".utf8)) }
                    exit(error == nil ? 0 : 1)
                }
            }
            if files.isEmpty {
                // Legacy versions understand standard reopen, but not the new launch-intent protocol.
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration, completionHandler: completion)
            } else {
                NSWorkspace.shared.open(files.map { URL(fileURLWithPath: $0) }, withApplicationAt: bundleURL,
                                        configuration: configuration, completionHandler: completion)
            }
            return
        }
        do {
            let url = lease.directory.appendingPathComponent(UUID().uuidString + ".json")
            try JSONEncoder().encode(InstanceRequest(arguments: arguments, files: files)).write(to: url, options: .atomic)
            requestURL = url
            deadline = Date().addingTimeInterval(15)
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkAcknowledgement() }
            }
        } catch { fail(error.localizedDescription) }
    }

    private func checkAcknowledgement() {
        guard let requestURL else { return }
        if !FileManager.default.fileExists(atPath: requestURL.path) {
            if !files.isEmpty {
                let pending = files
                files.removeAll()
                forward(arguments: [], files: pending)
            } else { exit(0) }
        } else if Date() > deadline {
            try? FileManager.default.removeItem(at: requestURL)
            fail("The running Mudsnote did not accept the launch request. Please retry after it finishes starting.")
        }
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
