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
        let result = try await ProcessRunner.run(
            "/usr/bin/env",
            [
                "swift", "build",
                "--package-path", temporary,
                "--configuration", "release",
                "--swift-sdk", sdk,
                "--build-system", "native",
            ]
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
