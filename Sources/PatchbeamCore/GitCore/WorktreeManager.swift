import Foundation

public struct WorktreeInfo: Codable, Sendable, Equatable {
    public var path: String
    public var branch: String
    public var baseCommit: String
}

/// Creates and removes **app-owned** worktrees under `AppPaths.worktrees`. It never
/// touches a path outside that directory and never overwrites an existing path or branch.
public struct WorktreeManager: Sendable {
    public let git: GitClient
    public let paths: AppPaths
    /// Refuse to create a worktree when free space falls below this.
    public var minimumFreeBytes: Int64 = 200 * 1024 * 1024

    public init(git: GitClient, paths: AppPaths) {
        self.git = git
        self.paths = paths
    }

    public func create(repoRoot: URL, capsuleID: UUID, baseCommit: String) async throws -> WorktreeInfo {
        try paths.ensureExists()
        if let free = try? paths.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < minimumFreeBytes {
            throw PatchbeamError(.diskSpace, "Disk space is low (\(free / 1_000_000) MB free). Patchbeam stopped before creating a worktree.",
                                 recovery: "Free some space or remove old capsules.")
        }
        let target = paths.worktree(for: capsuleID)
        guard PathSafety.isContained(target, in: paths.worktrees) else {
            throw PatchbeamError(.pathEscape, "Worktree path escaped Patchbeam's folder; refusing to continue.")
        }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw PatchbeamError(.worktreeFailed, "Worktree creation failed because \(target.path) already exists.",
                                 recovery: "Patchbeam never overwrites existing folders.")
        }
        let branch = try await uniqueBranch(repoRoot: repoRoot, capsuleID: capsuleID)
        let r = try await git.run(["worktree", "add", "--no-track", "-b", branch, target.path, baseCommit], in: repoRoot)
        guard r.succeeded else {
            throw PatchbeamError(.worktreeFailed, "Worktree creation failed because Git reported an error.",
                                 recovery: "Your repository was left unchanged.", detail: r.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return WorktreeInfo(path: PathSafety.canonical(target).path, branch: branch, baseCommit: baseCommit)
    }

    func uniqueBranch(repoRoot: URL, capsuleID: UUID) async throws -> String {
        let short = String(capsuleID.uuidString.lowercased().prefix(8))
        for attempt in 0..<20 {
            let name = attempt == 0 ? "patchbeam/\(short)" : "patchbeam/\(short)-\(attempt + 1)"
            let exists = try await git.run(["show-ref", "--verify", "--quiet", "refs/heads/\(name)"], in: repoRoot)
            if exists.exitCode != 0 { return name }
        }
        throw PatchbeamError(.worktreeFailed, "Worktree creation failed because no unused patchbeam/ branch name was available.")
    }

    public func registeredWorktrees(repoRoot: URL) async throws -> [String] {
        let out = try await git.checked(["worktree", "list", "--porcelain"], in: repoRoot)
        return out.split(separator: "\n").compactMap { line in
            line.hasPrefix("worktree ") ? PathSafety.canonical(URL(fileURLWithPath: String(line.dropFirst(9)))).path : nil
        }
    }

    public struct RemovalResult: Sendable, Equatable {
        public var removedWorktree: Bool
        public var deletedBranch: Bool
        public var note: String?
    }

    /// Remove an app-owned worktree. The branch is deleted only when it still points at the
    /// base commit (nothing new on it); otherwise it is kept and reported.
    public func remove(repoRoot: URL, info: WorktreeInfo) async throws -> RemovalResult {
        let url = URL(fileURLWithPath: info.path, isDirectory: true)
        guard PathSafety.isContained(url, in: paths.worktrees), url.standardizedFileURL != paths.worktrees.standardizedFileURL else {
            throw PatchbeamError(.pathEscape, "Refusing to remove \(info.path): it isn't a Patchbeam-owned worktree.")
        }
        guard info.branch.hasPrefix("patchbeam/") else {
            throw PatchbeamError(.pathEscape, "Refusing to delete branch \(info.branch): it isn't a Patchbeam branch.")
        }
        var removed = false
        if FileManager.default.fileExists(atPath: url.path) {
            let registered = try await registeredWorktrees(repoRoot: repoRoot)
            guard registered.contains(PathSafety.canonical(url).path) else {
                throw PatchbeamError(.pathEscape, "Refusing to remove \(info.path): Git doesn't list it as a worktree of this repository.")
            }
            try await git.checked(["worktree", "remove", "--force", url.path], in: repoRoot,
                                  code: .worktreeFailed, message: "Couldn't remove the repair worktree.")
            removed = true
        } else {
            _ = try await git.run(["worktree", "prune"], in: repoRoot)
        }
        let tip = try await git.run(["rev-parse", "--verify", "--quiet", "refs/heads/\(info.branch)"], in: repoRoot)
        if tip.succeeded {
            if tip.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == info.baseCommit {
                try await git.checked(["branch", "-D", info.branch], in: repoRoot)
                return RemovalResult(removedWorktree: removed, deletedBranch: true, note: nil)
            }
            return RemovalResult(removedWorktree: removed, deletedBranch: false,
                                 note: "Branch \(info.branch) has new commits, so Patchbeam kept it.")
        }
        return RemovalResult(removedWorktree: removed, deletedBranch: false, note: nil)
    }
}
