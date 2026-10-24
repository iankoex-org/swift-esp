import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Captured result of a child process.
public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }

    /// Combined output, in the order the shell would have interleaved it only
    /// approximately (stdout first, then stderr).
    public var combinedOutput: String {
        stdout + stderr
    }
}

public enum ProcessRunner {
    /// Runs a process and captures its output.
    public static func run(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil
    ) async throws -> CommandResult {
        var overrides: [Environment.Key: String?] = [:]
        for (key, value) in environment {
            overrides[Environment.Key(stringLiteral: key)] = value
        }
        let childEnvironment: Environment =
            environment.isEmpty ? .inherit : .inherit.updating(overrides)

        let result = try await Subprocess.run(
            .path(FilePath(executable)),
            arguments: Arguments(arguments),
            environment: childEnvironment,
            workingDirectory: workingDirectory.map { FilePath($0) },
            output: .string(limit: 256 * 1024 * 1024),
            error: .string(limit: 256 * 1024 * 1024)
        )

        let status: Int32
        switch result.terminationStatus {
            case .exited(let code):
                status = code
            case .signaled(let signal):
                status = 128 + signal
        }

        return CommandResult(
            status: status,
            stdout: result.standardOutput,
            stderr: result.standardError
        )
    }

    /// Runs a process and throws `ToolError` when it exits non-zero.
    @discardableResult
    public static func runChecking(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        context: String? = nil
    ) async throws -> CommandResult {
        let result = try await run(
            executable,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        guard result.succeeded else {
            let label = context.map { "\($0): " } ?? ""
            let detail = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolError(
                detail.isEmpty
                    ? "\(label)\(executable) exited with status \(result.status)"
                    : "\(label)\(detail)"
            )
        }
        return result
    }
}
