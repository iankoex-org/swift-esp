//
//  EspLog.swift
//  ESPBindings
//
//  Hand-maintained; formerly emitted by the build-time generator.
//

import CESPIDF
import CESPShims

/// Ergonomic, level-based logging over ESP-IDF's `esp_log` API.
///
/// Messages route through the `CESPShims` C shim because the underlying
/// `ESP_LOG_LEVEL_LOCAL` is a function-like macro the ClangImporter cannot
/// import.
public enum EspLog {
    /// Log verbosity, matching ESP-IDF's `esp_log_level_t`.
    public enum Level: UInt32, Sendable {
        case none = 0
        case error = 1
        case warn = 2
        case info = 3
        case debug = 4
        case verbose = 5
    }

    /// Sets the maximum level logged for `tag`.
    public static func setLevel(_ level: Level, for tag: String) {
        esp_log_level_set(tag, esp_log_level_t(level.rawValue))
    }

    /// Logs `message` at `level` under `tag`.
    public static func log(_ level: Level, _ tag: String, _ message: String) {
        shim_esp_log_level_local(esp_log_level_t(level.rawValue), tag, message)
    }

    public static func error(_ tag: String, _ message: String) { log(.error, tag, message) }
    public static func warn(_ tag: String, _ message: String) { log(.warn, tag, message) }
    public static func info(_ tag: String, _ message: String) { log(.info, tag, message) }
    public static func debug(_ tag: String, _ message: String) { log(.debug, tag, message) }
    public static func verbose(_ tag: String, _ message: String) { log(.verbose, tag, message) }
}
