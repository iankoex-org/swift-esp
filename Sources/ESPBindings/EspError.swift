//
//  EspError.swift
//  ESPBindings
//
//  Hand-maintained; formerly emitted by the build-time generator.
//

import CESPIDF
import CESPShims

/// Error thrown by generated ESP-IDF wrappers when an `esp_err_t` call
/// does not return `ESP_OK`.
public struct EspError: Error, Sendable {
    /// The raw `esp_err_t` value (`Int32` in ESP-IDF v6).
    public let code: Int32

    public init(code: Int32) {
        self.code = code
    }

    /// Well-known ESP-IDF error codes (subset; see `esp_err.h`).
    public static let ok = EspError(code: 0)
    public static let fail = EspError(code: 1)
    public static let noMem = EspError(code: 0x101)
    public static let invalidArg = EspError(code: 0x102)
    public static let invalidState = EspError(code: 0x103)
    public static let timeout = EspError(code: 0x107)
    public static let notFound = EspError(code: 0x105)

    /// Returns true when this code is `ESP_OK`.
    public var isOK: Bool { code == 0 }

    /// Human-readable name for well-known codes.
    public var name: String {
        switch code {
        case 0: return "ESP_OK"
        case 1: return "ESP_FAIL"
        case 0x101: return "ESP_ERR_NO_MEM"
        case 0x102: return "ESP_ERR_INVALID_ARG"
        case 0x103: return "ESP_ERR_INVALID_STATE"
        case 0x105: return "ESP_ERR_NOT_FOUND"
        case 0x107: return "ESP_ERR_TIMEOUT"
        case 0x201: return "ESP_ERR_NVS_NOT_INITIALIZED"
        case 0x202: return "ESP_ERR_NVS_NOT_FOUND"
        case 0x203: return "ESP_ERR_NVS_TYPE_MISMATCH"
        case 0x204: return "ESP_ERR_NVS_READ_ONLY"
        case 0x205: return "ESP_ERR_NVS_NOT_ENOUGH_SPACE"
        case 0x206: return "ESP_ERR_NVS_INVALID_NAME"
        case 0x207: return "ESP_ERR_NVS_INVALID_HANDLE"
        default: return "ESP_ERR_0x" + String(code, radix: 16)
        }
    }
}

/// Runs a call returning `esp_err_t` and throws `EspError` on failure.
///
/// - Parameter body: A closure returning the raw `esp_err_t`.
@discardableResult
public func espCall(_ body: () -> esp_err_t) throws -> esp_err_t {
    let code = body()
    guard code == 0 else { throw EspError(code: code) }
    return code
}