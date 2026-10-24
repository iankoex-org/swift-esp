import Foundation
import Testing

@testable import ESPSDKCore

@Suite("Versions and targets")
struct VersionTests {
    @Test("Swift version parsing normalizes to three components")
    func swiftVersion() {
        #expect(Versions.swiftVersion(from: "Swift version 6.4.1 (swift-6.4.1-RELEASE)") == "6.4.1")
        #expect(Versions.swiftVersion(from: "Swift version 6.4 (swift-6.4-RELEASE)") == "6.4.0")
        #expect(Versions.swiftVersion(from: "no version here") == nil)
    }

    @Test("ESP-IDF version prefers version.txt")
    func idfVersionFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try "v6.1\n".write(toFile: FileOps.join(root, "version.txt"), atomically: true, encoding: .utf8)
        #expect(await Versions.idfVersion(idfPath: root) == "6.1")
    }

    @Test("ESP-IDF version falls back to version.cmake")
    func idfVersionCMake() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let cmake = """
            set(IDF_VERSION_MAJOR 6)
            set(IDF_VERSION_MINOR 1)
            set(IDF_VERSION_PATCH 0)
            """
        try FileOps.write(cmake, to: FileOps.join(root, "tools/cmake/version.cmake"))
        #expect(await Versions.idfVersion(idfPath: root) == "6.1")
    }

    @Test("Target to GCC toolchain mapping")
    func targetMapping() throws {
        #expect(try Targets.toolchainName(for: "esp32c6") == "riscv32-esp-elf")
        #expect(throws: ToolError.self) { try Targets.toolchainName(for: "esp32s3") }
        #expect(throws: ToolError.self) { try Targets.toolchainName(for: "esp32x") }
    }

    @Test("Natural version ordering")
    func naturalOrder() {
        let values = ["esp-13.2.0_20230928", "esp-15.2.0_20251204", "esp-9.0.0"]
            .sorted(by: naturalCompare)
        #expect(values.last == "esp-15.2.0_20251204")
    }
}

@Suite("Target flags")
struct TargetFlagsTests {
    @Test("Derives triple, march and mabi from compile_commands")
    func fromCompileCommands() throws {
        let json = """
            [{"file": "/tmp/main.c",
              "command": "/tools/riscv32-esp-elf-gcc -march=rv32imac_zicsr_zifencei -mabi=ilp32 -c main.c"}]
            """
        let flags = try TargetFlags.derive(compileCommands: Data(json.utf8), cflags: nil)
        #expect(flags.triple == "riscv32-none-none-eabi")
        #expect(flags.march == "rv32imac_zicsr_zifencei")
        #expect(flags.mabi == "ilp32")
    }

    @Test("Falls back to cflags and strips vendor extensions")
    func cflagsFallback() throws {
        let json = """
            [{"file": "/tmp/main.c", "command": "/tools/riscv32-esp-elf-gcc -c main.c"}]
            """
        let flags = try TargetFlags.derive(
            compileCommands: Data(json.utf8),
            cflags: "-march=rv32imac_xvendor\n"
        )
        #expect(flags.march == "rv32imac")
        #expect(flags.mabi == "ilp32")
    }

    @Test("Rejects output without a RISC-V compiler")
    func rejectsNonRiscv() {
        let json = #"[{"file": "/tmp/main.c", "command": "/tools/clang -march=x86-64 -c main.c"}]"#
        #expect(throws: ToolError.self) {
            try TargetFlags.derive(compileCommands: Data(json.utf8), cflags: nil)
        }
    }
}

@Suite("EIM resolution")
struct EIMTests {
    @Test("Prefers the selected finished installation")
    func selection() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let activation = FileOps.join(root, "activate.sh")
        try FileOps.write("#!/bin/sh\n", to: activation)

        let json = """
            {
              "idfInstalled": [
                {"id": "a", "name": "v6.1", "path": "/idf/a", "idfToolsPath": "/tools/a",
                 "activationScript": "\(activation)", "status": "finished"},
                {"id": "b", "name": "v6.1", "path": "/idf/b", "idfToolsPath": "/tools/b",
                 "activationScript": "\(activation)", "status": "in_progress"}
              ],
              "idfSelectedId": "a"
            }
            """
        let state = FileOps.join(root, "eim_idf.json")
        try FileOps.write(json, to: state)

        let installation = try EIM.resolve(jsonPathOverride: state)
        #expect(installation.idfPath == "/idf/a")

        let byName = try EIM.resolve(name: "v6.1", jsonPathOverride: state)
        #expect(byName.idfPath == "/idf/a")
    }

    @Test("Missing state file produces a helpful error")
    func missingState() {
        #expect(throws: ToolError.self) {
            try EIM.resolve(jsonPathOverride: "/definitely/missing/eim_idf.json")
        }
    }
}

@Suite("Include directory rules")
struct IncludeTests {
    @Test("Collects -I flags, vendored components, and skips host-only components")
    func includeRules() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let idfPath = FileOps.join(root, "idf")
        let extra = FileOps.join(root, "extra/include")
        let other = FileOps.join(root, "other/include")
        let wifiInclude = FileOps.join(idfPath, "components/esp_wifi/include")
        let wifiTarget = FileOps.join(idfPath, "components/esp_wifi/esp32c6/include")
        let linuxInclude = FileOps.join(idfPath, "components/linux/include")
        let btAPI = FileOps.join(idfPath, "components/bt/common/api/include/api")

        for directory in [extra, other, wifiInclude, wifiTarget, linuxInclude, btAPI] {
            try FileOps.ensureDirectory(directory)
        }

        let command = "/tools/riscv32-esp-elf-gcc -I\(extra) -I \(other) -c main.c"
        let compile = """
            [{"file": "/tmp/main.c", "command": "\(command)"}]
            """

        let directories = try IncludeCollector.includeDirectories(
            compileCommands: Data(compile.utf8),
            idfPath: idfPath,
            target: "esp32c6"
        )

        #expect(directories.first == extra)
        #expect(directories.contains(other))
        #expect(directories.contains(wifiInclude))
        #expect(directories.contains(wifiTarget))
        #expect(directories.contains(btAPI))
        #expect(!directories.contains(linuxInclude))
        #expect(Set(directories).count == directories.count)
    }
}

@Suite("File operations")
struct FileOpsTests {
    @Test("copyTree dereferences symlinks and merges directories")
    func copyTree() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let source = FileOps.join(root, "source")
        let destination = FileOps.join(root, "destination")
        try FileOps.ensureDirectory(FileOps.join(source, "sub"))
        try FileOps.write("hello", to: FileOps.join(source, "sub/file.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: FileOps.join(source, "link.txt"),
            withDestinationPath: FileOps.join(source, "sub/file.txt")
        )

        try FileOps.copyTree(from: source, to: destination)

        #expect(try String(contentsOfFile: FileOps.join(destination, "link.txt"), encoding: .utf8) == "hello")
        #expect(try FileOps.symlinks(in: destination).isEmpty)
    }
}

@Suite("Templates")
struct TemplateTests {
    @Test("Bundle metadata is valid JSON")
    func metadataJSON() throws {
        let flags = TargetFlags(triple: "riscv32-none-none-eabi", march: "rv32imac", mabi: "ilp32")
        let documents = [
            Templates.swiftSDKJSON(triple: flags.triple),
            Templates.toolsetJSON(flags: flags),
            Templates.artifactInfoJSON(
                name: "swift-6.4.1_esp32c6-idf6.1-0.1.0",
                supportedTriples: Templates.supportedHostTriples,
                version: "0.1.0"
            ),
        ]
        for document in documents {
            let data = try #require(document.data(using: .utf8))
            #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
        }
    }

    @Test("Probe package points at the checkout")
    func probePackage() {
        let package = Templates.probePackage(repoPath: "/tmp/swift-esp")
        #expect(package.contains(".package(name: \"swift-esp\", path: \"/tmp/swift-esp\")"))
        #expect(package.contains("ESPBindings"))
    }
}

@Suite("Bundle portability")
struct PortabilityTests {
    @Test("Rejects symlinks in the bundle")
    func rejectsSymlinks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let bundle = FileOps.join(root, "bundle")
        try FileOps.ensureDirectory(bundle)
        try FileOps.write("x", to: FileOps.join(bundle, "file"))
        try FileManager.default.createSymbolicLink(
            atPath: FileOps.join(bundle, "link"),
            withDestinationPath: FileOps.join(bundle, "file")
        )

        #expect(throws: ToolError.self) {
            try BundleBuilder.checkPortability(bundle: bundle, idfPath: "/idf", sysroot: "/sysroot")
        }
    }

    @Test("Rejects build-machine paths")
    func rejectsLeaks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let bundle = FileOps.join(root, "bundle")
        try FileOps.ensureDirectory(bundle)
        try FileOps.write("home is \(FileOps.homeDirectory())\n", to: FileOps.join(bundle, "file"))

        #expect(throws: ToolError.self) {
            try BundleBuilder.checkPortability(bundle: bundle, idfPath: "/idf", sysroot: "/sysroot")
        }
    }

    @Test("Accepts a clean bundle")
    func acceptsCleanBundle() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let bundle = FileOps.join(root, "bundle")
        try FileOps.ensureDirectory(bundle)
        try FileOps.write("clean\n", to: FileOps.join(bundle, "file"))

        try BundleBuilder.checkPortability(bundle: bundle, idfPath: "/idf", sysroot: "/sysroot")
    }
}

private func temporaryDirectory() throws -> String {
    let path = FileOps.join(
        NSTemporaryDirectory(),
        "esp-sdk-tests-\(UUID().uuidString)"
    )
    try FileOps.ensureDirectory(path)
    return path
}
