import Foundation

public enum HeaderCheck {
    public static let defaultSDKID = "swift-6.4.1_esp32c6-idf6.1-0.1.0"

    public static func run(sdkID: String?, repoPath: String?) async throws {
        let environment = EnvironmentResolver.environment()
        let sdk = sdkID ?? environment["SWIFT_ESP_SDK_ID"] ?? defaultSDKID
        let repo = ((repoPath ?? FileOps.currentDirectory()) as NSString).expandingTildeInPath

        guard FileOps.exists(FileOps.join(repo, "Package.swift")) else {
            throw ToolError("error: no Package.swift at \(repo)")
        }

        let temporary = FileOps.join(
            NSTemporaryDirectory(),
            "swift-esp-headers-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(atPath: temporary) }

        let probeDirectory = FileOps.join(temporary, "Sources/Probe")
        try FileOps.ensureDirectory(probeDirectory)
        try FileOps.write(Templates.probePackage(repoPath: repo), to: FileOps.join(temporary, "Package.swift"))
        try FileOps.write(Templates.probeSource, to: FileOps.join(probeDirectory, "Probe.swift"))

        print("building header probe with SDK '\(sdk)'...")

        var arguments = [
            "build",
            "--package-path", temporary,
            "--configuration", "release",
            "--swift-sdk", sdk,
            "--build-system", "native",
        ]
        let executable: String
        if let swift = ExecutableLookup.path(named: "swift") {
            executable = swift
        } else {
            executable = "/usr/bin/env"
            arguments.insert("swift", at: 0)
        }

        // Resolve the real compiler: on swiftly installs `swiftc` on PATH is a
        // proxy, and pinning SWIFTPM_CUSTOM_BIN_DIR to the proxy breaks it.
        var swiftcPath = ExecutableLookup.path(named: "swiftc")
        if let swiftly = ExecutableLookup.path(named: "swiftly"),
            let resolved = try? await ProcessRunner.run(swiftly, ["run", "which", "swiftc"]),
            resolved.succeeded
        {
            let candidate = resolved.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { swiftcPath = candidate }
        }

        var toolchainEnvironment: [String: String] = [:]
        if let swiftcPath {
            toolchainEnvironment["SWIFTPM_CUSTOM_BIN_DIR"] =
                (swiftcPath as NSString).deletingLastPathComponent
        }

        let result = try await ProcessRunner.run(
            executable,
            arguments,
            environment: toolchainEnvironment
        )

        if !result.stdout.isEmpty { print(result.stdout, terminator: "") }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        guard result.succeeded else {
            throw ToolError("header probe failed with status \(result.status)")
        }
        print("header probe: OK")
    }
}
