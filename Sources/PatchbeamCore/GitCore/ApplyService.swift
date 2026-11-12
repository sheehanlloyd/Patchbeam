import Foundation

public struct ApplyOutcome: Sendable, Equatable {
    public var appliedFiles: [String]
    public var patchPath: String
    /// How to undo: the exact reverse-apply command (shown, never run automatically).
    public var rollbackCommand: [String]
}

/// Applies a verified patch to the user's working tree **without committing**, failing
/// closed on any mismatch. Never uses reset, clean, checkout --force or stash (PRD §12.4).
public actor ApplyService {
    private let git: GitClient
    private var inFlight: Set<String> = []

    public init(git: GitClient) {
        self.git = git
    }

    public func apply(
        patchFile: URL,
        changedFiles: [ChangedFile],
        repoRoot: URL,
        expectedBase: String
    ) async throws -> ApplyOutcome {
        let key = PathSafety.canonical(repoRoot).path
        guard inFlight.insert(key).inserted else {
            throw PatchbeamError(.applyInProgress, "Another patch is being applied to this repository.", recovery: "Wait for it to finish.")
        }
        defer { inFlight.remove(key) }

        // 1. The destination must still be exactly the base the agent started from.
        let head = try await git.run(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], in: repoRoot)
        let currentHead = head.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard head.succeeded, currentHead == expectedBase else {
            throw PatchbeamError(.destinationMoved, "Your branch has changed; automatic apply is paused.",
                                 recovery: "Open the repair worktree and merge manually.",
                                 detail: "expected \(expectedBase.prefix(8)), found \(currentHead.prefix(8))")
        }

        // 2. None of the touched paths may have uncommitted edits (or exist untracked).
        let touched = Array(Set(changedFiles.flatMap { [$0.path] + ($0.oldPath.map { [$0] } ?? []) })).sorted()
        if !touched.isEmpty {
            let status = try await git.checked(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--"] + touched, in: repoRoot)
            let dirty = status.split(separator: "\0").filter { $0.count > 3 }.map { String($0.dropFirst(3)) }
            guard dirty.isEmpty else {
                throw PatchbeamError(.destinationDirty, "Your uncommitted edits touch the same files; automatic apply is paused.",
                                     recovery: "Commit or stash your edits yourself, or merge from the worktree manually.",
                                     detail: dirty.joined(separator: ", "))
            }
        }

        // 3. Dry run.
        let applyArgs = ["apply", "--binary", "--whitespace=nowarn"]
        let check = try await git.run(applyArgs + ["--check", patchFile.path], in: repoRoot)
        guard check.succeeded else {
            throw PatchbeamError(.applyConflict, "The patch doesn't apply cleanly; nothing was changed.",
                                 recovery: "Open the repair worktree and merge manually.", detail: check.stderrString)
        }

        // 4. Apply to the working tree only (no index, no commit).
        let applied = try await git.run(applyArgs + [patchFile.path], in: repoRoot)
        guard applied.succeeded else {
            throw PatchbeamError(.applyConflict, "Git refused to apply the patch.", detail: applied.stderrString)
        }

        // 5. Post-apply verification: the reverse patch must apply, proving the exact patch is present.
        let verify = try await git.run(applyArgs + ["-R", "--check", patchFile.path], in: repoRoot)
        guard verify.succeeded else {
            throw PatchbeamError(.applyConflict, "Patch applied but post-apply verification failed. Review your working tree.",
                                 detail: verify.stderrString)
        }
        return ApplyOutcome(
            appliedFiles: changedFiles.map(\.path),
            patchPath: patchFile.path,
            rollbackCommand: ["git", "apply", "-R", "--binary", patchFile.path]
        )
    }
}
