import Foundation

public struct BundleOptions: Sendable {
    public var target: String?
    public var eimIDF: String?
    public var idfPath: String?
    public var sysroot: String?
    public var swiftc: String?
    public var outDirectory: String?
    public var revision: String

    public init(
        target: String? = nil,
        eimIDF: String? = nil,
        idfPath: String? = nil,
        sysroot: String? = nil,
        swiftc: String? = nil,
        outDirectory: String? = nil,
        revision: String = "0.1.0"
    ) {
        self.target = target
        self.eimIDF = eimIDF
        self.idfPath = idfPath
        self.sysroot = sysroot
        self.swiftc = swiftc
        self.outDirectory = outDirectory
        self.revision = revision
    }
}

public enum BundleBuilder {
    public static func build(_ options: BundleOptions) async throws {
        let env = EnvironmentResolver.environment()
        let target = options.target ?? env["IDF_TARGET"] ?? "esp32c6"
        let out = FileOps.absolute(options.outDirectory ?? "sdk/build")
        let revision = options.revision

        let idf = try EnvironmentResolver.idf(explicitPath: options.idfPath, eimName: options.eimIDF)

        let toolchainName = try Targets.toolchainName(for: target)
        let sysroot: String
        if let explicit = options.sysroot {
            sysroot = FileOps.absolute(explicit)
            let include = FileOps.join(sysroot, toolchainName, "include")
            guard FileOps.isDirectory(include) else {
                throw ToolError("error: bad sysroot: \(sysroot) (expected \(include))")
            }
        } else {
            sysroot = try EnvironmentResolver.sysroot(target: target, toolsPath: idf.toolsPath)
        }

        let swiftc = try await EnvironmentResolver.swiftc(explicit: options.swiftc)
        let toolchainBin = EnvironmentResolver.toolchainBin(swiftc: swiftc)

        print("swiftc:     \(swiftc)")
        print("toolchain:  \(toolchainBin)")
        print("sysroot:    \(sysroot)")
        print("IDF_PATH:   \(idf.idfPath)")
        print("IDF name:   \(idf.name.isEmpty ? "<custom>" : idf.name)")

        let swiftVersionOutput = try await ProcessRunner.run(swiftc, ["-version"])
        guard
            let swiftVersion = Versions.swiftVersion(
                from: swiftVersionOutput.combinedOutput
            )
        else {
            throw ToolError("error: could not determine Swift or ESP-IDF version")
        }
        guard let idfVersion = await Versions.idfVersion(idfPath: idf.idfPath) else {
            throw ToolError("error: could not determine Swift or ESP-IDF version")
        }
        let bundleName = "swift-\(swiftVersion)_\(target)-idf\(idfVersion)-\(revision)"
        print("sdk id:     \(bundleName)")

        // ---------- collect ESP-IDF include dirs ----------
        let scratch = FileOps.join(out, "scratch-idf")
        let includes = try await IncludeCollector.collect(
            IncludeOptions(
                target: target,
                idfPath: idf.idfPath,
                activationScript: idf.activationScript,
                scratchPath: scratch,
                logsPath: out
            )
        )
        print("collected \(includes.count) include dirs")

        // ---------- C library include dir ----------
        let cflagsFile = FileOps.join(scratch, "build/toolchain/cflags")
        let newlibInclude = FileOps.join(sysroot, toolchainName, "include")
        var cLibraryInclude = newlibInclude
        if let cflags = try? String(contentsOfFile: cflagsFile, encoding: .utf8),
            cflags.contains("picolibc.specs")
        {
            cLibraryInclude = FileOps.join(sysroot, "picolibc/include")
        }
        guard FileOps.isDirectory(cLibraryInclude) else {
            throw ToolError("error: C library include dir not found: \(cLibraryInclude)")
        }
        print("C library include: \(cLibraryInclude)")

        // ---------- target flags ----------
        let compileCommands = FileOps.join(scratch, "build/compile_commands.json")
        guard let compileData = try? Data(contentsOf: URL(fileURLWithPath: compileCommands)) else {
            throw ToolError("error: missing \(compileCommands)")
        }
        let cflagsText = try? String(contentsOfFile: cflagsFile, encoding: .utf8)
        let flags: TargetFlags
        do {
            flags = try TargetFlags.derive(compileCommands: compileData, cflags: cflagsText)
        } catch {
            throw ToolError("error: failed to derive triple/-march/-mabi for \(target)")
        }
        print("triple: \(flags.triple)  march: \(flags.march)  mabi: \(flags.mabi)")

        // ---------- assemble bundle ----------
        let bundle = FileOps.join(out, bundleName)
        try FileOps.removeIfExists(bundle)
        let sdkRootInclude = FileOps.join(bundle, "sdk-root/include")
        let includeRoot = FileOps.join(bundle, "include")
        try FileOps.ensureDirectory(sdkRootInclude)
        try FileOps.ensureDirectory(includeRoot)

        try FileOps.copyContents(of: newlibInclude, to: sdkRootInclude)
        let picolibcInclude = FileOps.join(bundle, "picolibc/include")
        if cLibraryInclude != newlibInclude {
            try FileOps.copyContents(of: cLibraryInclude, to: picolibcInclude)
        }

        try copyIDFHeaders(
            includes: includes,
            cLibraryInclude: cLibraryInclude,
            destination: includeRoot
        )

        // Expose GCC's float.h for picolibc's sys/config.h.
        if let floatHeader = findGCCFloatHeader(sysroot: sysroot, toolchainName: toolchainName),
            !FileOps.exists(FileOps.join(includeRoot, "float.h"))
        {
            try FileOps.copyFile(from: floatHeader, to: FileOps.join(includeRoot, "float.h"))
        }

        guard FileOps.exists(FileOps.join(includeRoot, "sdkconfig.h")) else {
            throw ToolError("error: sdkconfig.h was not collected from the scratch IDF build")
        }
        print("IDF include/: \(try FileOps.regularFiles(in: includeRoot).count) files")

        try copyBluetoothLayout(idfPath: idf.idfPath, target: target, bundle: bundle)
        try await copySwiftResources(toolchainBin: toolchainBin, triple: flags.triple, bundle: bundle)
        try writeMetadata(bundle: bundle, triple: flags.triple)
        try writeWrappers(bundle: bundle)
        try writeToolset(bundle: bundle, flags: flags)

        try checkPortability(bundle: bundle, idfPath: idf.idfPath, sysroot: sysroot)
        try await packageArtifactBundle(
            bundle: bundle,
            name: bundleName,
            out: out,
            swiftc: swiftc,
            revision: revision
        )
    }

    // MARK: - Header assembly

    static func copyIDFHeaders(
        includes: [String],
        cLibraryInclude: String,
        destination: String
    ) throws {
        for directory in includes {
            let entries = try FileOps.contents(of: directory).filter { !$0.hasPrefix(".") }

            // Flat headers, unless the C library owns the name.
            for name in entries where name.hasSuffix(".h") {
                let path = FileOps.join(directory, name)
                guard !FileOps.isDirectory(path) else { continue }
                if FileOps.exists(FileOps.join(cLibraryInclude, name))
                    || FileOps.exists(FileOps.join(cLibraryInclude, "sys", name))
                {
                    continue
                }
                try FileOps.copyFile(from: path, to: FileOps.join(destination, name))
            }

            // Prefix-style includes ("freertos/FreeRTOS.h", "soc/...").
            for name in entries {
                let path = FileOps.join(directory, name)
                guard FileOps.isDirectory(path) else { continue }
                let target = FileOps.join(destination, name)
                try FileOps.ensureDirectory(target)
                try copyVisibleContents(of: path, to: target)
            }
        }
    }

    /// Copies a header tree the way the shell's `copy_tree` did: dotfiles are
    /// skipped at every level because shell globs do not match them.
    static func copyVisibleContents(of source: String, to destination: String) throws {
        try FileOps.ensureDirectory(destination)
        for name in try FileOps.contents(of: source) where !name.hasPrefix(".") {
            let path = FileOps.join(source, name)
            let target = FileOps.join(destination, name)
            if FileOps.isDirectory(path) {
                try FileOps.ensureDirectory(target)
                try copyVisibleContents(of: path, to: target)
            } else {
                try FileOps.copyFile(from: path, to: target)
            }
        }
    }

    static func findGCCFloatHeader(sysroot: String, toolchainName: String) -> String? {
        let root = FileOps.join(sysroot, ["lib/gcc", toolchainName])
        guard FileOps.isDirectory(root) else { return nil }
        let versions = ((try? FileOps.contents(of: root)) ?? []).sorted()
        for version in versions.reversed() {
            let candidate = FileOps.join(root, [version, "include/float.h"])
            if FileOps.exists(candidate) { return candidate }
        }
        return nil
    }

    static func copyBluetoothLayout(idfPath: String, target: String, bundle: String) throws {
        let btRoot = FileOps.join(idfPath, "components/bt")
        let configuration = FileOps.join(btRoot, ["controller", target, "esp_bt_cfg.h"])
        guard FileOps.exists(configuration) else { return }

        let destination = FileOps.join(bundle, ["bt/controller", target])
        try FileOps.ensureDirectory(destination)
        try FileOps.copyFile(
            from: configuration,
            to: FileOps.join(destination, "esp_bt_cfg.h")
        )

        let api = FileOps.join(btRoot, "common/api/include/api")
        if FileOps.isDirectory(api) {
            try FileOps.copyContents(
                of: api,
                to: FileOps.join(bundle, "bt/common/api/include/api")
            )
        }
    }

    // MARK: - Swift resources

    static func copySwiftResources(toolchainBin: String, triple: String, bundle: String) async throws {
        let swiftResources = URL(fileURLWithPath: FileOps.join(toolchainBin, "../lib/swift"))
            .resolvingSymlinksInPath().path
        let embeddedSource = FileOps.join(swiftResources, "embedded")
        guard FileOps.isDirectory(embeddedSource) else {
            throw ToolError(
                "error: no embedded stdlib at \(embeddedSource)/embedded — toolchain too old?"
            )
        }

        let embeddedDestination = FileOps.join(bundle, "swift-resources/embedded")
        try FileOps.ensureDirectory(embeddedDestination)

        for name in try FileOps.contents(of: embeddedSource) {
            let path = FileOps.join(embeddedSource, name)
            guard !FileOps.isDirectory(path) else { continue }
            try FileOps.copyFile(from: path, to: FileOps.join(embeddedDestination, name))
        }

        // Keep only the target triple's slice of prebuilt modules.
        for name in try FileOps.contents(of: embeddedSource) where name.hasSuffix(".swiftmodule") {
            let path = FileOps.join(embeddedSource, name)
            if FileOps.isDirectory(path) {
                let destination = FileOps.join(embeddedDestination, name)
                try FileOps.ensureDirectory(destination)
                for file in try FileOps.contents(of: path) where file.hasPrefix("\(triple).") {
                    try FileOps.copyFile(
                        from: FileOps.join(path, file),
                        to: FileOps.join(destination, file)
                    )
                }
            } else {
                try FileOps.copyFile(from: path, to: FileOps.join(embeddedDestination, name))
            }
        }

        let tripleResources = FileOps.join(embeddedSource, triple)
        if FileOps.isDirectory(tripleResources) {
            try FileOps.copyTree(
                from: tripleResources,
                to: FileOps.join(embeddedDestination, triple)
            )
        }

        for extra in ["shims", "module.modulemap"] {
            let source = FileOps.join(swiftResources, extra)
            guard FileOps.exists(source) else { continue }
            try FileOps.copyTree(
                from: source,
                to: FileOps.join(bundle, "swift-resources", extra)
            )
        }

        // Clang builtin resources. On macOS lib/swift/clang is a symlink; on
        // Linux use lib/clang/<version> directly.
        var clangSource = FileOps.join(swiftResources, "clang")
        if !FileOps.isDirectory(FileOps.join(clangSource, "include")) {
            let root = FileOps.join(toolchainBin, "../lib/clang")
            let versions = ((try? FileOps.contents(of: root)) ?? []).sorted(by: naturalCompare)
            if let version = versions.last {
                clangSource = FileOps.join(root, version)
            }
        }
        guard FileOps.isDirectory(FileOps.join(clangSource, "include")) else {
            throw ToolError("error: clang builtin headers not found in the toolchain")
        }

        let clangDestination = FileOps.join(bundle, "swift-resources/clang")
        try FileOps.copyTree(
            from: FileOps.join(clangSource, "include"),
            to: FileOps.join(clangDestination, "include")
        )
        let share = FileOps.join(clangSource, "share")
        if FileOps.isDirectory(share) {
            try FileOps.copyTree(from: share, to: FileOps.join(clangDestination, "share"))
        }

        let builtins = FileOps.join(clangDestination, ["lib", triple])
        try FileOps.ensureDirectory(builtins)
        try await ProcessRunner.runChecking(
            FileOps.join(toolchainBin, "llvm-ar"),
            ["rcs", FileOps.join(builtins, "libclang_rt.builtins.a")]
        )
    }

    // MARK: - Metadata

    static func writeMetadata(bundle: String, triple: String) throws {
        try writeText(Templates.swiftSDKJSON(triple: triple), to: FileOps.join(bundle, "swift-sdk.json"))
    }

    static func writeToolset(bundle: String, flags: TargetFlags) throws {
        try writeText(Templates.toolsetJSON(flags: flags), to: FileOps.join(bundle, "toolset.json"))
    }

    static func writeWrappers(bundle: String) throws {
        let bin = FileOps.join(bundle, "bin")
        try FileOps.ensureDirectory(bin)
        try writeText(Templates.findToolchain, to: FileOps.join(bin, "_find-toolchain.sh"))
        try writeText(Templates.swiftcWrapper, to: FileOps.join(bin, "swiftc"), executable: true)
        try writeText(Templates.clangWrapper, to: FileOps.join(bin, "clang"), executable: true)
        try writeText(Templates.clangPlusPlusWrapper, to: FileOps.join(bin, "clang++"), executable: true)
    }

    static func writeText(_ text: String, to path: String, executable: Bool = false) throws {
        let normalized = text.hasSuffix("\n") ? text : text + "\n"
        try FileOps.write(normalized, to: path, executable: executable)
    }

    // MARK: - Portability checks

    static func checkPortability(bundle: String, idfPath: String, sysroot: String) throws {
        let links = try FileOps.symlinks(in: bundle)
        if !links.isEmpty {
            throw ToolError(
                "error: bundle contains \(links.count) symlink(s); it would not be portable\n"
                    + links.prefix(20).joined(separator: "\n")
            )
        }

        let needles = [FileOps.homeDirectory(), idfPath, sysroot].filter { !$0.isEmpty }
        var leaks: [String] = []
        for file in try FileOps.regularFiles(in: bundle) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
                FileOps.isText(data)
            else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if needles.contains(where: { text.contains($0) }) {
                leaks.append(file)
            }
        }
        if !leaks.isEmpty {
            throw ToolError(
                "error: bundle references build-machine paths:\n"
                    + leaks.prefix(20).joined(separator: "\n")
            )
        }
    }

    // MARK: - Packaging

    static func packageArtifactBundle(
        bundle: String,
        name: String,
        out: String,
        swiftc: String,
        revision: String
    ) async throws {
        let artifactBundle = FileOps.join(out, "\(name).artifactbundle")
        try FileOps.removeIfExists(artifactBundle)
        try FileOps.ensureDirectory(artifactBundle)
        try FileOps.copyTree(from: bundle, to: FileOps.join(artifactBundle, name))

        var supportedTriples = Templates.supportedHostTriples
        if let host = await Versions.hostTriple(swiftc: swiftc) {
            supportedTriples.append(host)
        }
        let info = Templates.artifactInfoJSON(
            name: name,
            supportedTriples: supportedTriples,
            version: revision
        )
        try writeText(info, to: FileOps.join(artifactBundle, "info.json"))

        let tarball = FileOps.join(out, "\(name).tar.gz")
        try FileOps.removeIfExists(tarball)
        try await ProcessRunner.runChecking(
            "/usr/bin/env",
            ["tar", "-C", out, "-czf", tarball, "\(name).artifactbundle"],
            environment: ["COPYFILE_DISABLE": "1"]
        )

        print("")
        print("bundle:        \(bundle)")
        print("tarball:       \(tarball)")
        print("expected sdk id: \(name)")
        print("")
        print("next:")
        print("  swift sdk install \(tarball)")
        print("  swift sdk list    # confirm the id matches .sourcekit-lsp/config.json")
    }
}
