import Foundation

public enum CodexRuntimeLocator {
    public static func resolve(configuredPath: String? = nil) -> URL? {
        resolve(
            configuredPath: configuredPath,
            environmentPath: ProcessInfo.processInfo.environment["PATH"],
            homeDirectory: NSHomeDirectory()
        )
    }

    public static func resolve(
        configuredPath: String?,
        environmentPath: String?,
        homeDirectory: String,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []
        if let configuredPath, !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(configuredPath)
        }
        if let environmentPath {
            candidates += environmentPath.split(separator: ":").map { String($0) + "/codex" }
        }
        candidates += [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]

        let nvmRoot = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates += versions
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin/codex").path }
        }

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            let expanded = NSString(string: path).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return nil
    }
}

public struct CodexAIProvider: Sendable {
    public let executableURL: URL
    public let workingDirectory: URL

    public init(executableURL: URL, workingDirectory: URL) {
        self.executableURL = executableURL
        self.workingDirectory = workingDirectory
    }

    public func generate(request: AIRequest) async throws -> String {
        let prompt = try AIPromptBuilder.prompt(for: request)
        return try await Task.detached(priority: .userInitiated) {
            try Self.run(
                executableURL: executableURL,
                workingDirectory: workingDirectory,
                prompt: prompt
            )
        }.value
    }

    public static func makeArguments(workingDirectory: URL, outputURL: URL) -> [String] {
        [
            "--ask-for-approval", "never",
            "exec",
            "--ephemeral",
            "--sandbox", "read-only",
            "--skip-git-repo-check",
            "--color", "never",
            "-C", workingDirectory.path,
            "--output-last-message", outputURL.path,
            "-"
        ]
    }

    private static func run(executableURL: URL, workingDirectory: URL, prompt: String) throws -> String {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("mudsnote-codex-output-\(UUID().uuidString).txt")
        let errorURL = fileManager.temporaryDirectory
            .appendingPathComponent("mudsnote-codex-error-\(UUID().uuidString).txt")
        _ = fileManager.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? errorHandle.close()
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: errorURL)
        }

        let inputPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = makeArguments(workingDirectory: workingDirectory, outputURL: outputURL)
        process.currentDirectoryURL = workingDirectory
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorHandle

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        environment["PATH"] = [
            executableURL.deletingLastPathComponent().path,
            environment["PATH"],
            "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ].compactMap { $0 }.joined(separator: ":")
        process.environment = environment

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(prompt.utf8))
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            throw AIError.localProviderUnavailable(executableURL.path)
        }

        guard process.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: errorURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AIError.requestFailed(detail.isEmpty ? "Codex 执行失败，退出码 \(process.terminationStatus)。" : String(detail.prefix(800)))
        }
        let output = (try? String(contentsOf: outputURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else { throw AIError.invalidResponse }
        return output
    }
}
