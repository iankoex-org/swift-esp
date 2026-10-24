import Foundation

/// One ESP-IDF installation recorded by EIM in `eim_idf.json`.
public struct EIMInstallation: Sendable, Equatable {
    public let id: String
    public let name: String
    public let idfPath: String
    public let toolsPath: String
    public let activationScript: String
    public let status: String

    public init(
        id: String,
        name: String,
        idfPath: String,
        toolsPath: String,
        activationScript: String,
        status: String
    ) {
        self.id = id
        self.name = name
        self.idfPath = idfPath
        self.toolsPath = toolsPath
        self.activationScript = activationScript
        self.status = status
    }
}

/// Reads the state file written by the ESP-IDF Installation Manager.
public enum EIM {
    public static func jsonPath(override: String? = nil) -> String {
        if let override { return override }
        if let environment = ProcessInfo.processInfo.environment["EIM_IDF_JSON"] {
            return environment
        }
        return FileOps.join(FileOps.homeDirectory(), ".espressif/tools/eim_idf.json")
    }

    public static func installations(jsonPathOverride: String? = nil) throws -> [EIMInstallation] {
        let path = jsonPath(override: jsonPathOverride)
        guard FileOps.exists(path) else {
            throw ToolError(
                """
                error: EIM configuration not found: \(path)
                       install ESP-IDF with: eim install -i v6.1 -t esp32c6
                       or pass --idf-path /path/to/esp-idf
                """
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw ToolError("error: cannot read \(path): \(error.localizedDescription)")
        }

        let state: State
        do {
            state = try JSONDecoder().decode(State.self, from: data)
        } catch {
            throw ToolError("error: cannot parse \(path): \(error.localizedDescription)")
        }

        let installations = (state.idfInstalled ?? []).compactMap { entry -> EIMInstallation? in
            guard let idfPath = entry.path, !idfPath.isEmpty else { return nil }
            return EIMInstallation(
                id: entry.id ?? "",
                name: entry.name ?? "",
                idfPath: idfPath,
                toolsPath: entry.idfToolsPath ?? "",
                activationScript: entry.activationScript ?? "",
                status: entry.status ?? ""
            )
        }

        guard !installations.isEmpty else {
            throw ToolError(
                "error: no EIM-managed ESP-IDF installation found; run: eim install -i v6.1 -t esp32c6"
            )
        }
        return installations
    }

    public static func resolve(
        name requested: String? = nil,
        jsonPathOverride: String? = nil
    ) throws -> EIMInstallation {
        let all = try installations(jsonPathOverride: jsonPathOverride)
        let finished = all.filter { $0.status == "finished" }
        let candidates = finished.isEmpty ? all : finished

        let entry: EIMInstallation?
        if let requested, !requested.isEmpty {
            entry = candidates.first { $0.name == requested || $0.id == requested }
            if entry == nil {
                let available = Set(all.map(\.name)).sorted().joined(separator: ", ")
                throw ToolError(
                    "no EIM ESP-IDF installation named '\(requested)' (available: \(available.isEmpty ? "none" : available))"
                )
            }
        } else {
            let selectedID = try selectedInstallationID(jsonPathOverride: jsonPathOverride)
            entry = candidates.first { $0.id == selectedID } ?? candidates.first
        }

        guard let entry else {
            throw ToolError("error: no EIM-managed ESP-IDF installation found")
        }
        guard !entry.activationScript.isEmpty, FileOps.exists(entry.activationScript) else {
            throw ToolError(
                """
                error: EIM activation script not found for \(entry.name.isEmpty ? "installation" : entry.name)
                       expected: \(entry.activationScript.isEmpty ? "<none>" : entry.activationScript)
                       repair with: eim fix \(entry.name)
                """
            )
        }
        return entry
    }

    private static func selectedInstallationID(jsonPathOverride: String? = nil) throws -> String? {
        let path = jsonPath(override: jsonPathOverride)
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let state = try? JSONDecoder().decode(State.self, from: data)
        else {
            return nil
        }
        return state.idfSelectedId
    }

    private struct State: Decodable {
        let idfInstalled: [Entry]?
        let idfSelectedId: String?
    }

    private struct Entry: Decodable {
        let activationScript: String?
        let id: String?
        let idfToolsPath: String?
        let name: String?
        let path: String?
        let status: String?
    }
}
