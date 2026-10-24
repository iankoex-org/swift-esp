//
//  Nvs.swift
//  ESPBindings
//
//  Hand-maintained; formerly emitted by the build-time generator.
//

import CESPIDF
import CESPShims

/// Ergonomic wrappers over the non-volatile-storage flash API
/// (`nvs_flash.h`).
public enum Nvs {
    /// Initializes the default NVS partition.
    ///
    /// If the partition contains an incompatible layout, the partition is
    /// erased and re-initialized, mirroring the common ESP-IDF pattern.
    public static func initialize() throws {
        let code = nvs_flash_init()
        guard code == 0 else {
            if code == ESP_ERR_NVS_NO_FREE_PAGES || code == ESP_ERR_NVS_NEW_VERSION_FOUND {
                try espCall { nvs_flash_erase() }
                try espCall { nvs_flash_init() }
                return
            }
            throw EspError(code: code)
        }
    }

    /// Opens a namespace for reading and writing.
    public static func open(_ namespace: String) throws -> NvsHandle {
        var handle: nvs_handle_t = 0
        try espCall { nvs_open(namespace, NVS_READWRITE, &handle) }
        return NvsHandle(handle: handle)
    }
}

/// A live NVS namespace handle. Changes are written on `commit()`.
public struct NvsHandle: ~Copyable {
    private let handle: nvs_handle_t

    init(handle: nvs_handle_t) {
        self.handle = handle
    }

    deinit {
        nvs_close(handle)
    }

    /// Stores a UTF-8 string value.
    public mutating func set(_ key: String, to value: String) throws {
        try espCall { nvs_set_str(handle, key, value) }
    }

    /// Stores an integer value.
    public mutating func set(_ key: String, to value: Int32) throws {
        try espCall { nvs_set_i32(handle, key, value) }
    }

    /// Reads a string value; returns nil when the key does not exist.
    public func string(_ key: String) -> String? {
        var length: UInt = 0
        if nvs_get_str(handle, key, nil, &length) != 0 { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(length))
        guard nvs_get_str(handle, key, &buffer, &length) == 0 else { return nil }
        buffer.removeLast()  // trailing NUL
        return String(decoding: buffer, as: UTF8.self)
    }

    /// Reads an integer value; returns nil when the key does not exist.
    public func int32(_ key: String) -> Int32? {
        var value: Int32 = 0
        guard nvs_get_i32(handle, key, &value) == 0 else { return nil }
        return value
    }

    /// Persists pending changes.
    public func commit() throws {
        try espCall { nvs_commit(handle) }
    }
}
