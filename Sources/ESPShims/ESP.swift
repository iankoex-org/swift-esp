import CESPShims

/// Swift-facing wrappers over the C shims in `CESPShims`.
public enum ESP {
    /// Blocks the current FreeRTOS task.
    @inline(__always)
    public static func delay(milliseconds: UInt32) {
        shim_delay_ms(milliseconds)
    }

    /// Busy-waits using the ROM delay loop.
    @inline(__always)
    public static func delay(microseconds: UInt32) {
        esp_rom_delay_us(microseconds)
    }

    @inline(__always)
    public static func ticks(fromMilliseconds milliseconds: UInt32) -> UInt32 {
        shim_ms_to_ticks(milliseconds)
    }

    @inline(__always)
    public static func milliseconds(fromTicks ticks: UInt32) -> UInt32 {
        shim_ticks_to_ms(ticks)
    }

    /// Equivalent to `ESP_ERROR_CHECK`: logs and aborts on failure.
    @inline(__always)
    public static func check(_ error: esp_err_t) {
        shim_esp_error_check(error)
    }

    @discardableResult
    public static func createTask(
        name: String,
        stackDepth: UInt32,
        priority: UInt32,
        argument: UnsafeMutableRawPointer? = nil,
        entry: @convention(c) (UnsafeMutableRawPointer?) -> Void
    ) -> Bool {
        name.withCString { cName in
            shim_x_task_create(
                entry,
                cName,
                stackDepth,
                argument,
                UBaseType_t(priority),
                nil
            ) == pdPASS
        }
    }
}
