import CESPShims

/// A logger that provides structured logging functionality for ESP-IDF applications.
///
/// The `Logger` struct allows logging messages at different severity levels
/// (error, warning, info, debug, verbose, none)
/// and integrates with ESP-IDF's logging system.
/// It supports customizable configuration for formatting, colors, timestamps, and other logging options.
///
/// Example usage:
/// ```swift
/// let logger = Logger(label: "MyApp")
/// logger.info("Application started")
/// logger.error("An error occurred")
///
/// // Custom configuration
/// var config = Logger.Configuration()
/// config.logLevel = .debug
/// let debugLogger = Logger(label: "DebugApp", configuration: config)
/// ```
public struct Logger {
    /// The default configuration used for logging when no specific configuration is provided.
    let defaultConfiguration: Configuration

    /// The label used to identify the source of log messages in the output.
    let label: String

    /// Initializes a new logger with the specified label and optional configuration.
    ///
    /// - Parameters:
    ///   - label: A string that identifies the source of log messages.
    ///   - configuration: The default configuration to use for logging. Defaults to a new `Configuration()` instance.
    public init(label: String, configuration: Configuration = Configuration()) {
        self.label = label
        self.defaultConfiguration = configuration
    }
}

extension Logger {
    /// Logs a message with the specified configuration.
    ///
    /// This is an internal method that interfaces directly with the ESP-IDF logging shim.
    ///
    /// - Parameters:
    ///   - configuration: The logging configuration to use.
    ///   - message: The message to log.
    private func _log(configuration: Configuration, message: String) {
        shim_esp_log_level_local(configuration.logLevel.espLevel, label, message)
    }

    /// Logs a message at the specified level using the default configuration.
    ///
    /// - Parameters:
    ///   - level: The log level for the message.
    ///   - message: The message to log.
    private func _log(level: Level, message: String) {
        var configuration = defaultConfiguration
        configuration.logLevel = level
        self._log(configuration: configuration, message: message)
    }

    /// Logs a message at the specified level with file, function, and line information.
    ///
    /// This method allows logging with automatic inclusion of context information.
    ///
    /// - Parameters:
    ///   - level: The log level for the message.
    ///   - message: The message parts to log (joined with ", ").
    ///   - file: The file name (automatically provided by #file).
    ///   - function: The function name (automatically provided by #function).
    ///   - line: The line number (automatically provided by #line).
    public func log(
        level: Level, message: String..., file: String = #file, function: String = #function, line: Int = #line
    ) {
        let messageString = "\(message.joined(separator: ", ")) • \(function) \(lastComponent(of: file)):\(line)"
        self._log(level: level, message: messageString)
    }

    /// Logs an error message.
    ///
    /// - Parameters:
    ///   - message: The error message parts to log.
    ///   - file: The file name (automatically provided).
    ///   - function: The function name (automatically provided).
    ///   - line: The line number (automatically provided).
    public func error(_ message: String..., file: String = #file, function: String = #function, line: Int = #line) {
        let messageString = "\(message.joined(separator: ", ")) • \(function) \(lastComponent(of: file)):\(line)"
        self._log(level: .error, message: messageString)
    }

    /// Logs a warning message.
    ///
    /// - Parameters:
    ///   - message: The warning message parts to log.
    ///   - file: The file name (automatically provided).
    ///   - function: The function name (automatically provided).
    ///   - line: The line number (automatically provided).
    public func warning(_ message: String..., file: String = #file, function: String = #function, line: Int = #line) {
        let messageString = "\(message.joined(separator: ", ")) • \(function) \(lastComponent(of: file)):\(line)"
        self._log(level: .warning, message: messageString)
    }

    /// Logs an informational message.
    ///
    /// - Parameters:
    ///   - message: The informational message parts to log.
    ///   - file: The file name (automatically provided).
    ///   - function: The function name (automatically provided).
    ///   - line: The line number (automatically provided).
    public func info(_ message: String..., file: String = #file, function: String = #function, line: Int = #line) {
        let messageString = "\(message.joined(separator: ", ")) • \(function) \(lastComponent(of: file)):\(line)"
        self._log(level: .info, message: messageString)
    }

    /// Logs a debug message.
    ///
    /// - Parameters:
    ///   - message: The debug message parts to log.
    ///   - file: The file name (automatically provided).
    ///   - function: The function name (automatically provided).
    ///   - line: The line number (automatically provided).
    public func debug(_ message: String..., file: String = #file, function: String = #function, line: Int = #line) {
        let messageString = "\(message.joined(separator: ", ")) • \(function) \(lastComponent(of: file)):\(line)"
        self._log(level: .debug, message: messageString)
    }

    /// Logs a verbose message.
    ///
    /// - Parameters:
    ///   - message: The verbose message parts to log.
    ///   - file: The file name (automatically provided).
    ///   - function: The function name (automatically provided).
    ///   - line: The line number (automatically provided).
    public func verbose(_ message: String..., file: String = #file, function: String = #function, line: Int = #line) {
        let messageString = "\(message.joined(separator: ", ")) • \(function) \(lastComponent(of: file)):\(line)"
        self._log(level: .verbose, message: messageString)
    }
}

extension Logger {
    /// Represents the different logging levels supported by the ESP-IDF logging system.
    ///
    /// These levels correspond to the `esp_log_level_t` enumeration in ESP-IDF.
    public enum Level: Int {
        /// No log output.
        case none = 0

        /// Critical errors where the software module cannot recover on its own.
        case error = 1

        /// Error conditions from which recovery measures have been taken.
        case warning = 2

        /// Information messages that describe the normal flow of events.
        case info = 3

        /// Extra information not necessary for normal use (values, pointers, sizes, etc.).
        case debug = 4

        /// Bigger chunks of debugging information or frequent messages that can flood the output.
        case verbose = 5

        /// Number of levels supported. Added for compatibility with `esp_log_level_t`.
        case max = 6

        /// Converts the level to the corresponding C `esp_log_level_t` value.
        var espLevel: esp_log_level_t {
            esp_log_level_t(rawValue: UInt32(self.rawValue))
        }
    }
}

extension Logger {

    /// Configuration options for the logger.
    ///
    /// This struct allows customization of logging behavior, including level, formatting options,
    /// and environment-specific settings.
    public struct Configuration {
        /// The log level to use for this configuration.
        public var logLevel: Logger.Level = .info

        /// Flag indicating if logging is from a constrained environment
        /// (e.g., bootloader, ISR, startup code, early log, or when the cache is disabled).
        /// In such cases, `esp_rom_vprintf` is used instead of `vprintf`.
        public var constrainedEnvironment: Bool = false

        /// Flag specifying whether the log message needs additional formatting.
        /// If set, `esp_log()` will add formatting elements like color, timestamp, and tag to the log message.
        public var requireFormatting: Bool = true

        /// Flag to disable color in log output.
        /// If set, log messages will not include color codes.
        public var disableColor: Bool = false

        /// Flag to disable timestamps in log output.
        /// If set, log messages will not include timestamps.
        public var disableTimestamp: Bool = false

        /// Flag to indicate binary mode.
        public var binaryMode: Bool = true

        /// Reserved for future use. Should be initialized to 0.
        public var reserved: Int = 0

        public init(
            logLevel: Level = .info,
            constrainedEnvironment: Bool = false,
            requireFormatting: Bool = true,
            disableColor: Bool = false,
            disableTimestamp: Bool = false,
            binaryMode: Bool = true,
            reserved: Int = 0
        ) {
            self.logLevel = logLevel
            self.constrainedEnvironment = constrainedEnvironment
            self.requireFormatting = requireFormatting
            self.disableColor = disableColor
            self.disableTimestamp = disableTimestamp
            self.binaryMode = binaryMode
            self.reserved = reserved
        }
    }
}

extension Logger {
    /// Returns the substring after the final '/' or '\' in `path`.
    ///
    /// This function works on minimal (embedded) Swift runtimes without using `range(of:)`, `NSString`, `URL`, or `split`
    /// to avoid issues with `_swift_stdlib_getNormData` when trying to use `file.split(separator: "/")`.
    ///
    /// - SeeAlso: [Embedded Swift Strings Documentation](https://docs.swift.org/embedded/documentation/embedded/strings/)
    ///
    /// - Parameter path: The file path to extract the last component from.
    /// - Returns: The last component of the path.
    private func lastComponent(of path: String) -> String {
        // UTF‑8 view of the string – always available.
        let utf8View = path.utf8

        var lastSlashOffset: Int? = nil  // byte offset of the last separator

        // Scan the UTF‑8 bytes once.
        var offset = 0
        for byte in utf8View {
            if byte == UInt8(ascii: "/") || byte == UInt8(ascii: "\\") {
                lastSlashOffset = offset  // remember this position
            }
            offset += 1
        }

        // No separator → the whole string is the component.
        guard let slashOffset = lastSlashOffset else {
            return path
        }

        // The component starts one byte after the separator.
        let startOffset = slashOffset + 1

        // Convert the byte offset to a `String.Index`.
        let startIndex = String.Index(utf16Offset: startOffset, in: path)

        // Slice from `startIndex` to the end of the original string.
        return String(path[startIndex...])
    }
}
