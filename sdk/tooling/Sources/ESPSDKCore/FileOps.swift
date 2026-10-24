import Foundation

/// Filesystem helpers with the semantics the bundle builder relies on:
/// symlinks are dereferenced when copying, and trees merge with source wins.
public enum FileOps {

    public static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public static func ensureDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public static func removeIfExists(_ path: String) throws {
        guard exists(path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }

    /// Sorted directory entry names (like shell globbing, but stable).
    public static func contents(of path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path).sorted()
    }

    /// Copies a file, following symlinks. Parent directories must exist or are
    /// created. POSIX permissions are preserved.
    public static func copyFile(from source: String, to destination: String) throws {
        try ensureDirectory((destination as NSString).deletingLastPathComponent)
        try removeIfExists(destination)
        let resolved = URL(fileURLWithPath: source).resolvingSymlinksInPath().path
        let data = try Data(contentsOf: URL(fileURLWithPath: resolved))
        try data.write(to: URL(fileURLWithPath: destination))
        if let permissions = try? FileManager.default.attributesOfItem(atPath: resolved)[.posixPermissions] {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination)
        }
    }

    /// Copies the *contents* of `source` into `destination`, merging and
    /// overwriting files. Symlinks are dereferenced.
    public static func copyContents(of source: String, to destination: String) throws {
        try ensureDirectory(destination)
        for name in try contents(of: source) {
            try copyEntry(from: join(source, name), to: join(destination, name))
        }
    }

    /// Copies `source` as a new entry at `destination` (like `cp -RL src dst`
    /// when `dst` does not exist).
    public static func copyTree(from source: String, to destination: String) throws {
        guard isDirectory(source) else {
            try copyFile(from: source, to: destination)
            return
        }
        try removeIfExists(destination)
        try ensureDirectory(destination)
        for name in try contents(of: source) {
            try copyEntry(from: join(source, name), to: join(destination, name))
        }
    }

    private static func copyEntry(from source: String, to destination: String) throws {
        let resolved = URL(fileURLWithPath: source).resolvingSymlinksInPath().path
        guard exists(resolved) else { return }
        if isDirectory(resolved) {
            try ensureDirectory(destination)
            for name in try contents(of: resolved) {
                try copyEntry(from: join(resolved, name), to: join(destination, name))
            }
        } else {
            try copyFile(from: resolved, to: destination)
        }
    }

    public static func write(_ text: String, to path: String, executable: Bool = false) throws {
        try ensureDirectory((path as NSString).deletingLastPathComponent)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: path
            )
        }
    }

    /// Every regular file below `root`, following directory symlinks.
    public static func regularFiles(in root: String) throws -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: []
            )
        else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url.path)
            }
        }
        return files.sorted()
    }

    /// Every symlink below `root`.
    public static func symlinks(in root: String) throws -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []
            )
        else {
            return []
        }

        var links: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                links.append(url.path)
            }
        }
        return links.sorted()
    }

    /// True when `data` looks like UTF-8 text (no NUL bytes), matching
    /// `grep -I`.
    public static func isText(_ data: Data) -> Bool {
        !data.contains(0)
    }

    public static func join(_ base: String, _ component: String) -> String {
        (base as NSString).appendingPathComponent(component)
    }

    public static func join(_ base: String, _ first: String, _ rest: String...) -> String {
        rest.reduce(join(base, first)) { join($0, $1) }
    }

    public static func join(_ base: String, _ components: [String]) -> String {
        components.reduce(base) { join($0, $1) }
    }

    public static func parent(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    /// Expands `~` and resolves relative paths against the current directory,
    /// so paths remain valid after a child process changes directory.
    public static func absolute(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        return (currentDirectory() as NSString).appendingPathComponent(expanded)
    }

    public static func lastComponent(of path: String) -> String {
        (path as NSString).lastPathComponent
    }

    public static func currentDirectory() -> String {
        FileManager.default.currentDirectoryPath
    }

    public static func homeDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }
}

/// Natural ordering for version-named directories (`esp-13.2.0` < `esp-15.2.0`),
/// mirroring `sort -V` closely enough for toolchain directories.
public func naturalCompare(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs)
    let right = Array(rhs)
    var i = 0
    var j = 0

    func number(at index: inout Int, in characters: [Character]) -> String? {
        guard index < characters.count, characters[index].isNumber else { return nil }
        var digits = ""
        while index < characters.count, characters[index].isNumber {
            digits.append(characters[index])
            index += 1
        }
        return digits
    }

    while i < left.count, j < right.count {
        if left[i].isNumber, right[j].isNumber {
            var li = i
            var rj = j
            let l = number(at: &li, in: left) ?? ""
            let r = number(at: &rj, in: right) ?? ""
            if l.count != r.count { return l.count < r.count }
            if l != r { return l < r }
            i = li
            j = rj
        } else {
            if left[i] != right[j] { return left[i] < right[j] }
            i += 1
            j += 1
        }
    }
    return left.count < right.count
}
