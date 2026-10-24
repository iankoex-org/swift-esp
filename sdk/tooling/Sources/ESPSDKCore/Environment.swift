import Foundation

public struct ResolvedIDF: Sendable {
    public let name: String
    public let idfPath: String
    public let toolsPath: String
    public let activationScript: String

    public init(name: String, idfPath: String, toolsPath: String, activationScript: String) {
        self.name = name
        self.idfPath = idfPath
        self.toolsPath = toolsPath
        self.activationScript = activationScript
    }
}

public enum EnvironmentResolver {
    public static func environment() -> [String: String] {
        ProcessInfo.processInfo.environment
    }

    /// Resolves ESP-IDF. An explicit path (or `$IDF_PATH`) wins; otherwise the
    /// EIM-selected installation is used.
    public static func idf(explicitPath: String?, eimName: String?) throws -> ResolvedIDF {
        let env = environment()
        let requestedPath = explicitPath ?? env["IDF_PATH"]
        let eim = try? EIM.resolve(name: eimName)

        if let requestedPath, !requestedPath.isEmpty {
            let path = (requestedPath as NSString).expandingTildeInPath
            if let eim, eim.idfPath == path {
                return ResolvedIDF(
                    name: eim.name,
                    idfPath: eim.idfPath,
                    toolsPath: env["ESP_TOOLS"] ?? eim.toolsPath,
                    activationScript: eim.activationScript
                )
            }
            let exportScript = FileOps.join(path, "export.sh")
            return ResolvedIDF(
                name: "",
                idfPath: path,
                toolsPath: env["ESP_TOOLS"]
                    ?? eim?.toolsPath
                    ?? FileOps.join(FileOps.homeDirectory(), ".espressif/tools"),
                activationScript: FileOps.exists(exportScript) ? exportScript : ""
            )
        }

        let installation = try EIM.resolve(name: eimName)
        return ResolvedIDF(
            name: installation.name,
            idfPath: installation.idfPath,
            toolsPath: env["ESP_TOOLS"] ?? installation.toolsPath,
            activationScript: installation.activationScript
        )
    }

    /// Finds `<tools>/riscv32-esp-elf/<version>/riscv32-esp-elf` and verifies
    /// its libc include directory.
    public static func sysroot(target: String, toolsPath: String) throws -> String {
        let toolchain = try Targets.toolchainName(for: target)
        let root = FileOps.join(toolsPath, toolchain)
        guard FileOps.isDirectory(root) else {
            throw ToolError(
                "error: no \(toolchain) toolchain under \(toolsPath) (install via ESP-IDF tools)"
            )
        }

        let versions = try FileOps.contents(of: root)
            .filter { FileOps.isDirectory(FileOps.join(root, $0)) }
            .sorted(by: naturalCompare)
        guard let version = versions.last else {
            throw ToolError(
                "error: no \(toolchain) toolchain under \(toolsPath) (install via ESP-IDF tools)"
            )
        }

        let sysroot = FileOps.join(root, version, toolchain)
        guard FileOps.isDirectory(FileOps.join(sysroot, toolchain, "include")) else {
            throw ToolError(
                "error: bad sysroot: \(sysroot) (expected \(FileOps.join(sysroot, toolchain, "include")))"
            )
        }
        return sysroot
    }

    /// Finds a swift.org toolchain with Embedded Swift support.
    public static func swiftc(explicit: String?) async throws -> String {
        let env = environment()

        if let explicit, !explicit.isEmpty {
            return try validateSwiftc((explicit as NSString).expandingTildeInPath)
        }
        if let fromEnvironment = env["SWIFTC"], !fromEnvironment.isEmpty {
            return try validateSwiftc((fromEnvironment as NSString).expandingTildeInPath)
        }

        if let swiftly = try? await ProcessRunner.run(
            "/usr/bin/env",
            ["swiftly", "run", "which", "swiftc"]
        ), swiftly.succeeded {
            let candidate = swiftly.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty, FileOps.exists(candidate) {
                return candidate
            }
        }

        let home = FileOps.homeDirectory()
        let patterns = [
            "\(home)/Library/Developer/toolchains/*/usr/bin/swiftc",
            "\(home)/Library/Developer/Toolchains/*/usr/bin/swiftc",
            "/Library/Developer/Toolchains/*/usr/bin/swiftc",
            "\(home)/.local/share/swiftly/toolchains/*/usr/bin/swiftc",
            "/usr/local/swift/usr/bin/swiftc",
        ]
        let found = patterns.flatMap { expandGlob($0) }.sorted()
        if let last = found.last {
            return try validateSwiftc(last)
        }

        if let optSwift = ["/opt/swift/bin/swiftc"].first(where: { FileOps.exists($0) }) {
            return try validateSwiftc(optSwift)
        }
        if let which = try? await ProcessRunner.run("/usr/bin/env", ["which", "swiftc"]),
            which.succeeded
        {
            let candidate = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty, FileOps.exists(candidate) {
                return try validateSwiftc(candidate)
            }
        }

        throw ToolError(
            """
            error: swiftc not found. Install a swift.org toolchain (Xcode's cannot target riscv32)
                   or pass --swiftc /path/to/swiftc
            """
        )
    }

    public static func toolchainBin(swiftc: String) -> String {
        URL(fileURLWithPath: swiftc).deletingLastPathComponent()
            .resolvingSymlinksInPath().path
    }

    private static func validateSwiftc(_ path: String) throws -> String {
        guard FileOps.exists(path), FileManager.default.isExecutableFile(atPath: path) else {
            throw ToolError("error: swiftc not found or not executable: \(path)")
        }
        return path
    }

    /// Minimal glob expansion for the fixed patterns above.
    private static func expandGlob(_ pattern: String) -> [String] {
        guard pattern.contains("*") else {
            return FileOps.exists(pattern) ? [pattern] : []
        }

        let parts = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var current = parts.first == "" ? ["/"] : ["."]

        for part in parts where !part.isEmpty {
            var next: [String] = []
            for base in current {
                if part.contains("*") {
                    guard let entries = try? FileOps.contents(of: base) else { continue }
                    next.append(contentsOf: entries.map { FileOps.join(base, $0) })
                } else {
                    next.append(FileOps.join(base, part))
                }
            }
            current = next
        }
        return current
    }
}
