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

    public static func restrictedAgentExecutable(
        from executableURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let resolved = executableURL.resolvingSymlinksInPath().standardizedFileURL
        if resolved.pathExtension != "js" {
            return fileManager.isExecutableFile(atPath: resolved.path) ? resolved : nil
        }

        let packageRoot = resolved
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #if arch(arm64)
        let target = "aarch64-apple-darwin"
        let package = "codex-darwin-arm64"
        #else
        let target = "x86_64-apple-darwin"
        let package = "codex-darwin-x64"
        #endif
        let candidates = [
            packageRoot
                .appendingPathComponent("node_modules/@openai/\(package)")
                .appendingPathComponent("vendor/\(target)/bin/codex"),
            packageRoot.appendingPathComponent("vendor/\(target)/bin/codex")
        ]
        return candidates.first {
            fileManager.isExecutableFile(atPath: $0.path)
        }?.standardizedFileURL
    }
}

public struct CodexAIProvider: Sendable {
    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    public func generate(request: AIRequest) async throws -> String {
        let prompt = try AIPromptBuilder.prompt(for: request)
        return try await generate(prompt: prompt)
    }

    public func generate(request: KnowledgeSynthesisRequest) async throws -> String {
        let prompt = try AIPromptBuilder.prompt(for: request)
        return try await generate(prompt: prompt)
    }

    private func generate(prompt: String) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard let agentExecutableURL = CodexRuntimeLocator.restrictedAgentExecutable(
                from: executableURL,
                fileManager: fileManager
            ) else {
                throw AIError.localProviderUnavailable(
                    "当前 Codex 安装无法以无工具隔离模式运行。"
                )
            }
            let isolatedWorkingDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "mudsnote-codex-\(UUID().uuidString)",
                    isDirectory: true
                )
            try fileManager.createDirectory(
                at: isolatedWorkingDirectory,
                withIntermediateDirectories: true
            )
            defer {
                try? fileManager.removeItem(at: isolatedWorkingDirectory)
            }
            return try Self.run(
                executableURL: agentExecutableURL,
                workingDirectory: isolatedWorkingDirectory,
                prompt: prompt
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    public static func makeArguments(workingDirectory: URL, outputURL: URL) -> [String] {
        [
            "--ask-for-approval", "never",
            "exec",
            "--ignore-user-config",
            "--ignore-rules",
            "--ephemeral",
            "--sandbox", "read-only",
            "--skip-git-repo-check",
            "--color", "never",
            "-C", workingDirectory.path,
            "--output-last-message", outputURL.path,
            "-"
        ]
    }

    public static func makeSandboxProfile(
        workingDirectory: URL,
        executableURL: URL
    ) -> String {
        let readRoots = sandboxReadRoots(for: executableURL)
        let runtimeReadRules = readRoots.map {
            "(subpath \"\(sandboxEscaped(sandboxCanonicalPath($0)))\")"
        }.joined(separator: "\n        ")
        let writableRoot = sandboxEscaped(sandboxCanonicalPath(workingDirectory))
        return """
        (version 1)
        (deny default)
        (allow process-info*)
        (allow process-fork)
        (allow process-exec
            (literal "\(sandboxEscaped(sandboxCanonicalPath(executableURL)))"))
        (allow signal (target self))
        (allow sysctl-read)
        (allow mach-lookup)
        (allow ipc-posix-shm)
        (allow network*)
        (allow file-read-metadata)
        (allow file-read-data
            (literal "/")
            \(runtimeReadRules)
            (subpath "\(writableRoot)"))
        (allow file-write*
            (subpath "/dev")
            (subpath "\(writableRoot)"))
        """
    }

    private static func run(
        executableURL: URL,
        workingDirectory: URL,
        prompt: String
    ) throws -> String {
        let fileManager = FileManager.default
        let codexHome = workingDirectory.appendingPathComponent(".codex", isDirectory: true)
        try fileManager.createDirectory(
            at: codexHome,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: codexHome.path
        )
        let userAuthURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex/auth.json")
        let isolatedAuthURL = codexHome.appendingPathComponent("auth.json")
        if fileManager.fileExists(atPath: userAuthURL.path),
           !fileManager.fileExists(atPath: isolatedAuthURL.path) {
            try fileManager.copyItem(at: userAuthURL, to: isolatedAuthURL)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: isolatedAuthURL.path
            )
        }

        let outputURL = workingDirectory
            .appendingPathComponent("mudsnote-codex-output-\(UUID().uuidString).txt")
        let errorURL = workingDirectory
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
        let sandboxExecutableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        guard fileManager.isExecutableFile(atPath: sandboxExecutableURL.path) else {
            throw AIError.localProviderUnavailable("系统知识草案隔离器不可用。")
        }
        process.executableURL = sandboxExecutableURL
        process.arguments = [
            "-p",
            makeSandboxProfile(
                workingDirectory: workingDirectory,
                executableURL: executableURL
            ),
            executableURL.path
        ] + makeArguments(workingDirectory: workingDirectory, outputURL: outputURL)
        process.currentDirectoryURL = workingDirectory
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorHandle

        process.environment = executionEnvironment(
            workingDirectory: workingDirectory,
            inheritedEnvironment: ProcessInfo.processInfo.environment
        )

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(prompt.utf8))
            inputPipe.fileHandleForWriting.closeFile()
            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    process.waitUntilExit()
                    throw CancellationError()
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } catch {
            if error is CancellationError {
                throw error
            }
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

    public static func executionEnvironment(
        workingDirectory: URL,
        inheritedEnvironment: [String: String]
    ) -> [String: String] {
        let codexHome = workingDirectory.appendingPathComponent(".codex", isDirectory: true)
        var environment: [String: String] = [
            "HOME": workingDirectory.path,
            "CODEX_HOME": codexHome.path,
            "TMPDIR": workingDirectory.path,
            "TERM": "dumb",
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        if let apiKey = inheritedEnvironment["OPENAI_API_KEY"], !apiKey.isEmpty {
            environment["OPENAI_API_KEY"] = apiKey
        }
        return environment
    }

    private static func sandboxReadRoots(for executableURL: URL) -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/usr", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            URL(fileURLWithPath: "/sbin", isDirectory: true),
            URL(fileURLWithPath: "/dev", isDirectory: true),
            URL(fileURLWithPath: "/private/etc", isDirectory: true),
            URL(fileURLWithPath: "/private/var/db", isDirectory: true),
            URL(fileURLWithPath: "/private/var/run", isDirectory: true),
            URL(fileURLWithPath: "/Library/Apple", isDirectory: true),
            executableURL,
            executableURL.resolvingSymlinksInPath()
        ]

        let homePath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL.path
        for url in [executableURL, executableURL.resolvingSymlinksInPath()] {
            let components = url.standardizedFileURL.pathComponents
            if let binIndex = components.lastIndex(of: "bin"),
               binIndex > 1,
               components.contains(".nvm")
                || components.contains("node_modules") {
                let runtimeRoot = URL(
                    fileURLWithPath: NSString.path(
                        withComponents: Array(components.prefix(binIndex))
                    ),
                    isDirectory: true
                )
                if runtimeRoot.standardizedFileURL.path != homePath {
                    roots.append(runtimeRoot)
                }
            }
            if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
                roots.append(
                    URL(
                        fileURLWithPath: NSString.path(
                            withComponents: Array(components.prefix(through: appIndex))
                        ),
                        isDirectory: true
                    )
                )
            }
        }

        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func sandboxEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func sandboxCanonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        for alias in ["/var", "/tmp", "/etc"] where path == alias || path.hasPrefix(alias + "/") {
            return "/private" + path
        }
        return path
    }
}
