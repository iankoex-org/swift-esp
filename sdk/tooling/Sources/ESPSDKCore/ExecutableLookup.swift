import Foundation

/// Locates an executable on `PATH` and returns its absolute path.
///
/// SwiftPM resolves its host toolchain bin directory from `argv[0]` relative to
/// the current directory. Invoking `swift` through `PATH` (argv[0] == "swift")
/// after `--package-path` changes directory therefore makes it look for
/// `<package>/swiftc`. Calling the resolved absolute path avoids that.
public enum ExecutableLookup {
    public static func path(named name: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PATH"] else { return nil }

        for directory in path.split(separator: ":") {
            let candidate = (String(directory) as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
