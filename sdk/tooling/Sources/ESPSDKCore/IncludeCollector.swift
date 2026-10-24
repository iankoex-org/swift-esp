import Foundation

public struct IncludeOptions: Sendable {
    public var target: String
    public var idfPath: String
    public var activationScript: String
    public var scratchPath: String
    public var logsPath: String

    public init(
        target: String,
        idfPath: String,
        activationScript: String,
        scratchPath: String,
        logsPath: String
    ) {
        self.target = target
        self.idfPath = idfPath
        self.activationScript = activationScript
        self.scratchPath = scratchPath
        self.logsPath = logsPath
    }
}

public enum IncludeCollector {
    /// Configures a scratch IDF project and returns the include directories in
    /// C search order.
    public static func collect(_ options: IncludeOptions) async throws -> [String] {
        guard !options.activationScript.isEmpty, FileOps.exists(options.activationScript) else {
            throw ToolError(
                "error: no activation script for ESP-IDF at \(options.idfPath); install it with EIM"
            )
        }

        try writeScratchProject(at: options.scratchPath)
        try FileOps.ensureDirectory(options.logsPath)

        let exportLog = FileOps.join(options.logsPath, "export.log")
        let setTargetLog = FileOps.join(options.logsPath, "set-target.log")
        let reconfigureLog = FileOps.join(options.logsPath, "reconfigure.log")

        let script = """
            . "$1" >"$2" 2>&1 || { echo "activation failed" >>"$2"; exit 11; }
            cd "$3" || exit 12
            set -o pipefail
            idf.py set-target "$4" 2>&1 | tee "$5" || exit 13
            idf.py reconfigure 2>&1 | tee "$6" || exit 14
            """

        let result = try await ProcessRunner.run(
            "/bin/bash",
            [
                "-c", script, "bash",
                options.activationScript,
                exportLog,
                options.scratchPath,
                options.target,
                setTargetLog,
                reconfigureLog,
            ]
        )
        guard result.succeeded else {
            let detail = result.combinedOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .suffix(4000)
            throw ToolError(
                """
                error: ESP-IDF activation or scratch project configuration failed (status \(result.status))
                       see \(exportLog), \(setTargetLog), \(reconfigureLog)
                \(detail)
                """
            )
        }

        let compileCommands = FileOps.join(options.scratchPath, "build/compile_commands.json")
        guard FileOps.exists(compileCommands) else {
            throw ToolError("error: idf.py reconfigure failed; no compile_commands.json")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: compileCommands))
        return try includeDirectories(compileCommands: data, idfPath: options.idfPath, target: options.target)
    }

    /// Pure include-directory rules, shared by the CLI and tests.
    public static func includeDirectories(
        compileCommands data: Data,
        idfPath: String,
        target: String
    ) throws -> [String] {
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
        var directories: [String] = []
        var seen = Set<String>()

        func add(_ path: String) {
            guard !path.isEmpty, !seen.contains(path), FileOps.isDirectory(path) else { return }
            seen.insert(path)
            directories.append(path)
        }

        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0
        while index < tokens.count {
            if tokens[index] == "-I", index + 1 < tokens.count {
                add(tokens[index + 1])
                index += 2
            } else if tokens[index].hasPrefix("-I") {
                add(String(tokens[index].dropFirst(2)))
                index += 1
            } else {
                index += 1
            }
        }

        let explicitComponents = [
            "esp_wifi", "nvs_flash", "esp_event", "esp_netif", "lwip",
            "log", "esp_timer", "driver", "esp_adc", "esp_system",
            "esp_common", "freertos", "hal", "soc", "esp_partition",
            "esp_blockdev", "nvs", "spi_flash", "esp_mm", "esp_rom",
            "esp_driver_gpio", "esp_driver_rmt", "esp_driver_ledc",
            "esp_driver_i2c", "esp_driver_spi", "esp_driver_uart",
            "esp_hal_gpio", "esp_hal_rmt", "esp_hal_ledc",
            "esp_hal_i2c", "esp_hal_spi", "esp_hal_uart",
            "esp_hal_dma", "esp_hal_clock",
        ]
        for component in explicitComponents {
            let base = FileOps.join(idfPath, ["components", component, "include"])
            add(base)
            add(FileOps.join(base, target))
        }

        // Vendor every component's standard public header dirs, so new APIs
        // are available without regenerating the bundle.
        let componentsRoot = FileOps.join(idfPath, "components")
        let hostOnly: Set<String> = [
            "linux", "windows", "host", "darwin", "test", "test_apps", "examples",
        ]
        if FileOps.isDirectory(componentsRoot) {
            for component in (try? FileOps.contents(of: componentsRoot)) ?? [] where !hostOnly.contains(component) {
                let base = FileOps.join(componentsRoot, component)
                guard FileOps.isDirectory(base) else { continue }
                add(FileOps.join(base, "include"))
                add(FileOps.join(base, ["include", target]))
                // Some components nest target headers one level deeper (BT) or
                // keep them under <component>/<target>/include (split HALs).
                add(FileOps.join(base, ["include", target, "include"]))
                add(FileOps.join(base, [target, "include"]))
            }
        }

        // BT/NimBLE/Bluedroid public API dirs are not under a plain include/.
        let btRoot = FileOps.join(componentsRoot, "bt")
        let btSubdirectories = [
            "host/nimble/nimble/nimble/include",
            "host/nimble/port/include",
            "host/nimble/nimble/port/include",
            "host/nimble/nimble/porting/npl/freertos/include",
            "porting/npl/freertos/include",
            "host/bluedroid/api/include/api",
            "host/bluedroid/api/include",
            "common/api/include/api",
            "common/include",
        ]
        for subdirectory in btSubdirectories {
            add(FileOps.join(btRoot, subdirectory))
        }

        return directories
    }

    private static func writeScratchProject(at scratch: String) throws {
        try FileOps.removeIfExists(scratch)
        try FileOps.ensureDirectory(FileOps.join(scratch, "main"))

        try FileOps.write(
            """
            cmake_minimum_required(VERSION 3.16)
            include($ENV{IDF_PATH}/tools/cmake/project.cmake)
            project(sdk_probe)
            """,
            to: FileOps.join(scratch, "CMakeLists.txt")
        )

        try FileOps.write(
            """
            idf_component_register(SRCS "main.c"
                REQUIRES esp_wifi nvs_flash esp_event esp_netif lwip log esp_timer
                         driver esp_adc esp_system esp_common freertos hal soc)
            """,
            to: FileOps.join(scratch, "main/CMakeLists.txt")
        )

        try FileOps.write(
            """
            #include "esp_log.h"
            #include "esp_wifi.h"
            #include "esp_bt.h"
            #include "nvs_flash.h"
            void app_main(void) {}
            """,
            to: FileOps.join(scratch, "main/main.c")
        )

        // Enable Wi-Fi and Bluetooth so the vendored sdkconfig.h carries the
        // CONFIG_BT_* defaults esp_bt.h expands.
        try FileOps.write(
            """
            CONFIG_BT_ENABLED=y
            CONFIG_BT_BLE_ENABLED=y
            CONFIG_BT_BLUEDROID_ENABLED=y
            CONFIG_BT_BLE_42_FEATURES_SUPPORTED=y
            """,
            to: FileOps.join(scratch, "sdkconfig.defaults")
        )
    }
}
