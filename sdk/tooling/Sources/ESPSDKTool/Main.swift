import ESPSDKCore
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct ESPSDKTool {
    static func main() async {
        do {
            try await CLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as ToolError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(error.exitCode)
        } catch {
            FileHandle.standardError.write(Data(("error: \(error)\n").utf8))
            exit(1)
        }
    }
}

enum CLI {
    static let usage = """
        esp-sdk — host tooling for swift-esp

        Usage:
          esp-sdk bundle [options]
          esp-sdk includes [options]
          esp-sdk check-headers [options]
          esp-sdk eim path [NAME]

        bundle options:
          --target TARGET      ESP-IDF target (default: esp32c6)
          --eim-idf NAME       EIM installation name (default: eim-selected)
          --idf-path PATH      custom ESP-IDF checkout
          --sysroot PATH       GCC sysroot (default: detected from EIM tools)
          --swiftc PATH        swift.org swiftc (default: discovered)
          --out DIR            output directory (default: sdk/build)

        includes options:
          --idf-target TARGET  ESP-IDF target (default: esp32c6)
          --eim-idf NAME       EIM installation name
          --idf-path PATH      custom ESP-IDF checkout
          --activation-script FILE
          --scratch DIR        scratch project (default: <out>/scratch-idf)
          --out DIR            log directory (default: sdk/build)

        check-headers options:
          --sdk-id ID          installed Swift SDK id
          --repo PATH          package root (default: current directory)
        """

    static func run(arguments: [String]) async throws {
        guard let command = arguments.first else {
            print(usage)
            return
        }
        let rest = Array(arguments.dropFirst())

        switch command {
            case "bundle":
                let parsed = try parse(
                    rest,
                    allowed: [
                        "--target", "--eim-idf", "--idf-path",
                        "--sysroot", "--swiftc", "--out",
                    ]
                )
                try await BundleBuilder.build(
                    BundleOptions(
                        target: parsed.options["--target"],
                        eimIDF: parsed.options["--eim-idf"],
                        idfPath: parsed.options["--idf-path"],
                        sysroot: parsed.options["--sysroot"],
                        swiftc: parsed.options["--swiftc"],
                        outDirectory: parsed.options["--out"]
                    )
                )

            case "includes":
                let parsed = try parse(
                    rest,
                    allowed: [
                        "--idf-target", "--target", "--eim-idf", "--idf-path",
                        "--activation-script", "--scratch", "--out",
                    ]
                )
                let environment = EnvironmentResolver.environment()
                let target =
                    parsed.options["--idf-target"]
                    ?? parsed.options["--target"]
                    ?? environment["IDF_TARGET"]
                    ?? "esp32c6"
                let idf = try EnvironmentResolver.idf(
                    explicitPath: parsed.options["--idf-path"],
                    eimName: parsed.options["--eim-idf"]
                )
                let activation = parsed.options["--activation-script"] ?? idf.activationScript
                let out = FileOps.absolute(parsed.options["--out"] ?? "sdk/build")
                let scratch = FileOps.absolute(parsed.options["--scratch"] ?? FileOps.join(out, "scratch-idf"))

                FileHandle.standardError.write(
                    Data("activating ESP-IDF \(idf.name.isEmpty ? idf.idfPath : idf.name)...\n".utf8)
                )
                let includes = try await IncludeCollector.collect(
                    IncludeOptions(
                        target: target,
                        idfPath: idf.idfPath,
                        activationScript: activation,
                        scratchPath: scratch,
                        logsPath: out
                    )
                )
                print(includes.joined(separator: "\n"))

            case "check-headers":
                let parsed = try parse(rest, allowed: ["--sdk-id", "--repo"])
                try await HeaderCheck.run(
                    sdkID: parsed.options["--sdk-id"],
                    repoPath: parsed.options["--repo"]
                )

            case "eim":
                guard rest.first == "path" else {
                    throw ToolError("error: usage: esp-sdk eim path [NAME]")
                }
                let installation = try EIM.resolve(name: rest.dropFirst().first)
                print(installation.idfPath)

            case "--help", "-h", "help":
                print(usage)

            default:
                throw ToolError("error: unknown command '\(command)'\n\n\(usage)")
        }
    }

    private struct Parsed {
        var options: [String: String] = [:]
        var positionals: [String] = []
    }

    private static func parse(_ arguments: [String], allowed: Set<String>) throws -> Parsed {
        var parsed = Parsed()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--help" || argument == "-h" {
                print(usage)
                exit(0)
            }
            if argument.hasPrefix("--") {
                let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
                let name = parts[0]
                guard allowed.contains(name) else {
                    throw ToolError("error: unknown option \(name)")
                }
                if parts.count == 2 {
                    parsed.options[name] = parts[1]
                    index += 1
                } else {
                    guard index + 1 < arguments.count else {
                        throw ToolError("error: missing value for \(name)")
                    }
                    parsed.options[name] = arguments[index + 1]
                    index += 2
                }
            } else {
                parsed.positionals.append(argument)
                index += 1
            }
        }
        return parsed
    }
}
