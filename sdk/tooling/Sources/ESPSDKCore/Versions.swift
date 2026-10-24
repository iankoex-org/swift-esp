import Foundation

public enum Targets {
    public static let riscv = [
        "esp32c2", "esp32c3", "esp32c5", "esp32c6",
        "esp32h2", "esp32h4", "esp32p4", "esp32c61",
    ]

    public static let xtensa = ["esp32", "esp32s2", "esp32s3"]

    /// GCC toolchain directory name for a target.
    public static func toolchainName(for target: String) throws -> String {
        if riscv.contains(target) { return "riscv32-esp-elf" }
        if xtensa.contains(target) {
            throw ToolError(
                """
                error: '\(target)' is Xtensa — needs Espressif's forked Swift toolchain,
                       which swift-sdk.json toolsets cannot drive yet. Use a RISC-V chip
                       (esp32c3/c6/h2/p4, ...) or contribute Xtensa support.
                """
            )
        }
        throw ToolError("error: unknown IDF target '\(target)'")
    }
}

public enum Versions {
    /// Extracts the Swift version from `swiftc -version` output and normalizes
    /// two-component versions to `x.y.0`.
    public static func swiftVersion(from output: String) -> String? {
        guard let match = output.firstMatch(of: /Swift version ([0-9]+\.[0-9]+(?:\.[0-9]+)?)/) else {
            return nil
        }
        let version = String(match.1)
        let components = version.split(separator: ".")
        return components.count == 2 ? version + ".0" : version
    }

    /// ESP-IDF version as `major.minor`, from `version.txt`, `version.cmake`,
    /// or `git describe` (EIM checkouts have no version.txt).
    public static func idfVersion(idfPath: String) async -> String? {
        let versionFile = FileOps.join(idfPath, "version.txt")
        if let text = try? String(contentsOfFile: versionFile, encoding: .utf8) {
            let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            if !version.isEmpty { return version }
        }

        let cmakeFile = FileOps.join(idfPath, "tools/cmake/version.cmake")
        if let text = try? String(contentsOfFile: cmakeFile, encoding: .utf8) {
            let major = text.firstMatch(of: /set\(IDF_VERSION_MAJOR[ \t]+([0-9]+)\)/).map { String($0.1) }
            let minor = text.firstMatch(of: /set\(IDF_VERSION_MINOR[ \t]+([0-9]+)\)/).map { String($0.1) }
            if let major, let minor { return "\(major).\(minor)" }
        }

        guard
            let git = try? await ProcessRunner.run(
                "/usr/bin/env",
                ["git", "-C", idfPath, "describe", "--tags", "--always"]
            ), git.succeeded
        else {
            return nil
        }
        let version = git.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
        return version.isEmpty ? nil : version
    }

    /// Host triple reported by the Swift toolchain (`swiftc -print-target-info`).
    public static func hostTriple(swiftc: String) async -> String? {
        guard let result = try? await ProcessRunner.run(swiftc, ["-print-target-info"]),
            result.succeeded,
            let data = result.stdout.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let target = object["target"] as? [String: Any],
            let triple = target["triple"] as? String
        else {
            return nil
        }
        return triple
    }
}

public struct TargetFlags: Sendable, Equatable {
    public let triple: String
    public let march: String
    public let mabi: String

    public init(triple: String, march: String, mabi: String) {
        self.triple = triple
        self.march = march
        self.mabi = mabi
    }

    /// Derives the target triple, `-march` and `-mabi` used by the scratch
    /// IDF build. IDF v5 puts them in compile_commands.json; v6 also writes
    /// them to `build/toolchain/cflags`.
    public static func derive(compileCommands data: Data, cflags: String?) throws -> TargetFlags {
        struct Entry: Decodable {
            let file: String?
            let command: String?
            let arguments: [String]?
        }

        let entries: [Entry]
        do {
            entries = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            throw ToolError("error: cannot parse compile_commands.json: \(error.localizedDescription)")
        }
        guard let entry = entries.first(where: { ($0.file ?? "").hasSuffix("main.c") }) ?? entries.first else {
            throw ToolError("error: compile_commands.json has no entries")
        }

        let command: String
        if let value = entry.command, !value.isEmpty {
            command = value
        } else {
            command = (entry.arguments ?? []).joined(separator: " ")
        }
        let compiler = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let compilerName = (compiler as NSString).lastPathComponent

        let triple: String? = compilerName.contains("riscv32") ? "riscv32-none-none-eabi" : nil

        var march: String?
        if let match = command.firstMatch(of: /-march=(\S+)/) {
            march = String(match.1)
        } else if let cflags, let match = cflags.firstMatch(of: /-march=(\S+)/) {
            march = String(match.1)
        }
        if let value = march {
            march = value.replacingOccurrences(of: "_x[^ ]*", with: "", options: .regularExpression)
        }

        var mabi: String?
        if let match = command.firstMatch(of: /-mabi=(\S+)/) {
            mabi = String(match.1)
        } else if triple != nil {
            mabi = "ilp32"
        }

        guard let triple, let march, let mabi else {
            throw ToolError("error: failed to derive triple/-march/-mabi for the target")
        }
        return TargetFlags(triple: triple, march: march, mabi: mabi)
    }
}
