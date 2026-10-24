import Foundation

/// An error with a user-facing message and a process exit code.
public struct ToolError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public let exitCode: Int32

    public init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }

    public var description: String { message }
}
