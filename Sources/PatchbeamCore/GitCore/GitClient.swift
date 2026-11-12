import Foundation

/// Argument-array Git invocation. Every call disables repository hooks and fsmonitor so
/// that selecting a repository never executes code from it.
public struct GitClient: Sendable {
    public let executable: URL
    private let runner = ProcessRunner()

    /// Safety flags prepended to every invocation.
    static let safetyArguments = [
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.fsmonitor=false",
        "-c", "diff.noprefix=false",
        "-c", "color.ui=false",
        "-c", "core.quotepath=false",
        "-c", "commit.gpgsign=false",
    ]

    public init(executable: URL) {
        self.executable = executable
    }

    public static func locate(searchPath: [String] = MinimalEnvironment.defaultSearchPath) throws -> GitClient {
        guard let url = ExecutableLocator.find("git", searchPath: searchPath) else {
            throw PatchbeamError(.gitMissing, "Git is missing.", recovery: "Install Xcode Command Line Tools (xcode-select --install) or Homebrew git.")
        }
        return GitClient(executable: url)
    }

    public func run(
        _ args: [String],
        in directory: URL,
        environment extra: [String: String] = [:],
        stdin: Data? = nil,
        timeout: Duration = .seconds(120),
        outputLimit: Int = 64 * 1024 * 1024
    ) async throws -> ProcessResult {
        var env = MinimalEnvironment.make(extra: ["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"])
        for (k, v) in extra { env[k] = v }
        let spec = ProcessSpec(
            executable: executable,
            arguments: Self.safetyArguments + args,
            workingDirectory: directory,
            environment: env,
            stdin: stdin,
            timeout: timeout,
            outputLimitBytes: outputLimit
        )
        return try await runner.run(spec)
    }

    /// Run and require exit 0; returns stdout trimmed of the trailing newline.
    @discardableResult
    public func checked(
        _ args: [String],
        in directory: URL,
        environment: [String: String] = [:],
        code: PatchbeamError.Code = .gitCommandFailed,
        message: String? = nil
    ) async throws -> String {
        let r = try await run(args, in: directory, environment: environment)
        guard r.succeeded else {
            throw PatchbeamError(code, message ?? "git \(args.first ?? "") failed.", detail: r.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var out = r.stdoutString
        if out.hasSuffix("\n") { out.removeLast() }
        return out
    }
}

/// Facts about a user repository gathered before anything is created (PRD §12.4).
public struct RepositorySnapshot: Sendable, Equatable {
    public var root: URL
    public var displayName: String
    public var head: String?
    public var branch: String?
    public var dirtyPaths: [String]
    public var untrackedCount: Int

    public var isDetached: Bool { head != nil && branch == nil }
    public var isDirty: Bool { !dirtyPaths.isEmpty }
    public var shortHead: String { head.map { String($0.prefix(8)) } ?? "none" }
}

public struct RepositoryInspector: Sendable {
    public let git: GitClient

    public init(git: GitClient) {
        self.git = git
    }

    public func inspect(_ folder: URL) async throws -> RepositorySnapshot {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw PatchbeamError(.notGitRepository, "Choose a folder containing a Git repository.")
        }
        let top = try await git.run(["rev-parse", "--show-toplevel"], in: folder)
        guard top.succeeded else {
            throw PatchbeamError(.notGitRepository, "Choose a folder containing a Git repository.",
                                 recovery: "Patchbeam won't run git init for you.", detail: top.stderrString)
        }
        let root = PathSafety.canonical(URL(fileURLWithPath: top.stdoutString.trimmingCharacters(in: .newlines), isDirectory: true))

        let headResult = try await git.run(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], in: root)
        let head = headResult.succeeded ? headResult.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        let branchResult = try await git.run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: root)
        let branch = branchResult.succeeded ? branchResult.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        let status = try await git.checked(["status", "--porcelain=v1", "-z", "--untracked-files=normal"], in: root)
        var dirty: [String] = []
        var untracked = 0
        var entries = status.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = entries.popFirst() {
            guard entry.count > 3 else { continue }
            let code = entry.prefix(2)
            let path = String(entry.dropFirst(3))
            if code == "??" { untracked += 1 } else { dirty.append(path) }
            if code.first == "R" || code.first == "C" { _ = entries.popFirst() }  // skip rename source
        }
        return RepositorySnapshot(
            root: root,
            displayName: root.lastPathComponent,
            head: head,
            branch: branch,
            dirtyPaths: dirty,
            untrackedCount: untracked
        )
    }
}
