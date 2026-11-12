import Foundation

/// Locations owned by Patchbeam. Everything lives under one user-deletable root
/// (`~/Library/Application Support/Patchbeam` by default, PRD §10.2).
public struct AppPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Default root, overridable with `PATCHBEAM_HOME` for tests, CI and the headless CLI.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppPaths {
        if let override = environment["PATCHBEAM_HOME"], !override.isEmpty {
            return AppPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return AppPaths(root: base.appendingPathComponent("Patchbeam", isDirectory: true))
    }

    public var database: URL { root.appendingPathComponent("patchbeam.sqlite") }
    public var worktrees: URL { root.appendingPathComponent("Worktrees", isDirectory: true) }
    public var capsules: URL { root.appendingPathComponent("Capsules", isDirectory: true) }

    public func capsuleDirectory(_ id: UUID) -> URL {
        capsules.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    public func worktree(for id: UUID) -> URL {
        worktrees.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    public func ensureExists() throws {
        for dir in [root, worktrees, capsules] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}

/// Builds the small, explicit environment handed to subprocesses. We never forward the
/// app's whole environment (PRD §12.3).
public enum MinimalEnvironment {
    public static let defaultSearchPath: [String] = [
        "\(NSHomeDirectory())/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    public static func make(
        searchPath: [String] = defaultSearchPath,
        extra: [String: String] = [:],
        source: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env: [String: String] = [
            "HOME": NSHomeDirectory(),
            "PATH": searchPath.joined(separator: ":"),
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "TERM": "dumb",
            "NO_COLOR": "1",
        ]
        for key in ["USER", "LOGNAME", "TMPDIR", "SHELL"] {
            if let value = source[key] { env[key] = value }
        }
        if env["TMPDIR"] == nil { env["TMPDIR"] = NSTemporaryDirectory() }
        for (k, v) in extra { env[k] = v }
        return env
    }
}

public enum ExecutableLocator {
    /// Resolve a bare program name against an explicit search path (no shell involved).
    public static func find(_ name: String, searchPath: [String] = MinimalEnvironment.defaultSearchPath) -> URL? {
        if name.contains("/") {
            let url = URL(fileURLWithPath: name)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        for dir in searchPath {
            let candidate = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// Canonical path helpers with symlink resolution, used before every filesystem decision.
public enum PathSafety {
    public static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// True when `child` resolves to `parent` or a descendant of it (after symlink resolution).
    public static func isContained(_ child: URL, in parent: URL) -> Bool {
        let c = canonical(child).pathComponents
        let p = canonical(parent).pathComponents
        guard c.count >= p.count else { return false }
        return Array(c.prefix(p.count)) == p
    }
}
