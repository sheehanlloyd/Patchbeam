import Foundation
import Testing
@testable import PatchbeamCore

@Suite("Git integration", .serialized)
struct GitIntegrationTests {
    @Test func inspectsRepoWithSpacesAndUnicode() async throws {
        let repo = try await TempRepo.make(name: "my repo ünï 日本")
        let snap = try await RepositoryInspector(git: repo.git).inspect(repo.root.appendingPathComponent("."))
        #expect(snap.root == repo.root)
        #expect(snap.displayName == "my repo ünï 日本")
        #expect(snap.branch == "main")
        #expect(snap.head?.count == 40)
        #expect(!snap.isDirty)
    }

    @Test func subdirectoryResolvesToTopLevel() async throws {
        let repo = try await TempRepo.make(files: ["src/a.txt": "a"])
        let snap = try await RepositoryInspector(git: repo.git).inspect(repo.root.appendingPathComponent("src"))
        #expect(snap.root == repo.root)
    }

    @Test func nonRepositoryIsRejected() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pb-norepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await #expect(throws: PatchbeamError.self) { try await RepositoryInspector(git: GitClient.locate()).inspect(dir) }
    }

    @Test func unbornHeadIsReported() async throws {
        let repo = try await TempRepo.make(files: [:])
        let snap = try await RepositoryInspector(git: repo.git).inspect(repo.root)
        #expect(snap.head == nil)
    }

    @Test func detachedHeadIsReported() async throws {
        let repo = try await TempRepo.make()
        let head = try await repo.head()
        try await repo.git.checked(["checkout", "-q", "--detach", head], in: repo.root)
        let snap = try await RepositoryInspector(git: repo.git).inspect(repo.root)
        #expect(snap.isDetached)
    }

    @Test func worktreeStartsFromHeadWithoutDirtyEditsOrUntrackedSecrets() async throws {
        let repo = try await TempRepo.make(files: ["app.py": "x = 1\n", ".gitignore": "*.local\n"])
        try repo.write("app.py", "x = 'uncommitted user edit'\n")
        try repo.write(".env", "API_KEY=secret\n")
        try repo.write("notes.local", "ignored\n")
        let snap = try await RepositoryInspector(git: repo.git).inspect(repo.root)
        #expect(snap.isDirty)
        #expect(snap.dirtyPaths == ["app.py"])

        let wm = WorktreeManager(git: repo.git, paths: repo.paths)
        let id = UUID()
        let wt = try await wm.create(repoRoot: repo.root, capsuleID: id, baseCommit: snap.head!)
        let wtURL = URL(fileURLWithPath: wt.path)
        #expect(try String(contentsOf: wtURL.appendingPathComponent("app.py"), encoding: .utf8) == "x = 1\n")
        #expect(!FileManager.default.fileExists(atPath: wtURL.appendingPathComponent(".env").path))
        #expect(!FileManager.default.fileExists(atPath: wtURL.appendingPathComponent("notes.local").path))
        #expect(wt.path.contains("Patchbeam Support/Worktrees"), "path with spaces handled")
        #expect(wt.branch == "patchbeam/\(id.uuidString.lowercased().prefix(8))")
        // The user's dirty edit is untouched.
        #expect(try repo.read("app.py") == "x = 'uncommitted user edit'\n")
        let listed = try await wm.registeredWorktrees(repoRoot: repo.root)
        #expect(listed.contains(wt.path))
    }

    @Test func repositoryHooksNeverRun() async throws {
        let repo = try await TempRepo.make()
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("pb-hook-ran-\(UUID().uuidString)")
        try repo.write(".git/hooks/post-checkout", "#!/bin/sh\ntouch '\(marker.path)'\n")
        chmod(repo.root.appendingPathComponent(".git/hooks/post-checkout").path, 0o755)
        let wm = WorktreeManager(git: repo.git, paths: repo.paths)
        _ = try await wm.create(repoRoot: repo.root, capsuleID: UUID(), baseCommit: try await repo.head())
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func branchCollisionGetsSuffixAndLeavesExistingBranch() async throws {
        let repo = try await TempRepo.make()
        let id = UUID()
        let short = id.uuidString.lowercased().prefix(8)
        try await repo.git.checked(["branch", "patchbeam/\(short)"], in: repo.root)
        let before = try await repo.git.checked(["rev-parse", "patchbeam/\(short)"], in: repo.root)
        let wt = try await WorktreeManager(git: repo.git, paths: repo.paths).create(repoRoot: repo.root, capsuleID: id, baseCommit: try await repo.head())
        #expect(wt.branch == "patchbeam/\(short)-2")
        #expect(try await repo.git.checked(["rev-parse", "patchbeam/\(short)"], in: repo.root) == before)
    }

    @Test func existingWorktreeFolderIsNeverOverwritten() async throws {
        let repo = try await TempRepo.make()
        let id = UUID()
        let target = repo.paths.worktree(for: id)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: target.appendingPathComponent("keep.txt"))
        await #expect(throws: PatchbeamError.self) {
            try await WorktreeManager(git: repo.git, paths: repo.paths).create(repoRoot: repo.root, capsuleID: id, baseCommit: try await repo.head())
        }
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("keep.txt").path))
    }

    @Test func diffCoversModifiedAddedDeletedRenamedAndBinary() async throws {
        let repo = try await TempRepo.make(files: [
            "keep.txt": "one\ntwo\n", "gone.txt": "bye\n",
            "old name.txt": String(repeating: "same content line\n", count: 20),
        ])
        let base = try await repo.head()
        let wt = try await WorktreeManager(git: repo.git, paths: repo.paths).create(repoRoot: repo.root, capsuleID: UUID(), baseCommit: base)
        let w = URL(fileURLWithPath: wt.path)
        try Data("one\nTWO\n".utf8).write(to: w.appendingPathComponent("keep.txt"))
        try FileManager.default.removeItem(at: w.appendingPathComponent("gone.txt"))
        try FileManager.default.moveItem(at: w.appendingPathComponent("old name.txt"), to: w.appendingPathComponent("new name.txt"))
        try Data("new\n".utf8).write(to: w.appendingPathComponent("added.txt"))
        try Data([0, 1, 2, 3, 255]).write(to: w.appendingPathComponent("blob.bin"))
        try FileManager.default.createDirectory(at: w.appendingPathComponent("__pycache__"), withIntermediateDirectories: true)
        try Data([1]).write(to: w.appendingPathComponent("__pycache__/x.pyc"))

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("pb-diff-\(UUID().uuidString)")
        let snap = try await DiffService(git: repo.git).snapshot(worktree: w, baseCommit: base, outputDirectory: out)
        let byPath = Dictionary(uniqueKeysWithValues: snap.artifact.changedFiles.map { ($0.path, $0) })
        #expect(byPath["keep.txt"]?.kind == .modified)
        #expect(byPath["keep.txt"]?.additions == 1 && byPath["keep.txt"]?.deletions == 1)
        #expect(byPath["gone.txt"]?.kind == .deleted)
        #expect(byPath["new name.txt"]?.kind == .renamed)
        #expect(byPath["new name.txt"]?.oldPath == "old name.txt")
        #expect(byPath["added.txt"]?.kind == .added)
        #expect(byPath["blob.bin"]?.isBinary == true)
        #expect(byPath["__pycache__/x.pyc"] == nil, "volatile build products excluded")
        #expect(snap.artifact.fingerprint.count == 64)
        // Worktree's real index untouched: git status still shows unstaged changes.
        let status = try await repo.git.checked(["status", "--porcelain"], in: w)
        #expect(status.contains(" M keep.txt"))
    }

    @Test func fingerprintIsStableAndContentSensitive() async throws {
        let repo = try await TempRepo.make(files: ["a.txt": "1\n"])
        let base = try await repo.head()
        let wt = try await WorktreeManager(git: repo.git, paths: repo.paths).create(repoRoot: repo.root, capsuleID: UUID(), baseCommit: base)
        let w = URL(fileURLWithPath: wt.path)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("pb-fp-\(UUID().uuidString)")
        let ds = DiffService(git: repo.git)
        try Data("2\n".utf8).write(to: w.appendingPathComponent("a.txt"))
        let a = try await ds.snapshot(worktree: w, baseCommit: base, outputDirectory: out).artifact.fingerprint
        let b = try await ds.snapshot(worktree: w, baseCommit: base, outputDirectory: out).artifact.fingerprint
        try Data("3\n".utf8).write(to: w.appendingPathComponent("a.txt"))
        let c = try await ds.snapshot(worktree: w, baseCommit: base, outputDirectory: out).artifact.fingerprint
        #expect(a == b)
        #expect(a != c)
    }

    /// Shared setup: base repo + worktree with an edit + snapshot.
    func preparedPatch(files: [String: String] = ["calc.py": "x = 1\n", "other.py": "y = 1\n"]) async throws -> (TempRepo, String, DiffService.Snapshot, WorktreeInfo) {
        let repo = try await TempRepo.make(files: files)
        let base = try await repo.head()
        let wt = try await WorktreeManager(git: repo.git, paths: repo.paths).create(repoRoot: repo.root, capsuleID: UUID(), baseCommit: base)
        try Data("x = 2\n".utf8).write(to: URL(fileURLWithPath: wt.path).appendingPathComponent("calc.py"))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("pb-apply-\(UUID().uuidString)")
        let snap = try await DiffService(git: repo.git).snapshot(worktree: URL(fileURLWithPath: wt.path), baseCommit: base, outputDirectory: out)
        return (repo, base, snap, wt)
    }

    @Test func applyWritesWorkingTreeOnlyAndNeverCommits() async throws {
        let (repo, base, snap, _) = try await preparedPatch()
        #expect(try repo.read("calc.py") == "x = 1\n", "source untouched before approval")
        let outcome = try await ApplyService(git: repo.git).apply(
            patchFile: URL(fileURLWithPath: snap.artifact.diffPath), changedFiles: snap.artifact.changedFiles,
            repoRoot: repo.root, expectedBase: base)
        #expect(try repo.read("calc.py") == "x = 2\n")
        #expect(try await repo.head() == base, "no commit created")
        let staged = try await repo.git.checked(["diff", "--cached", "--name-only"], in: repo.root)
        #expect(staged.isEmpty, "index untouched")
        #expect(outcome.rollbackCommand.contains("-R"))
    }

    @Test func applyPausesWhenBranchMoved() async throws {
        let (repo, base, snap, _) = try await preparedPatch()
        try repo.write("unrelated.txt", "new commit\n")
        try await repo.commitAll("user moved on")
        await #expect(throws: PatchbeamError.self) {
            try await ApplyService(git: repo.git).apply(patchFile: URL(fileURLWithPath: snap.artifact.diffPath),
                                                        changedFiles: snap.artifact.changedFiles, repoRoot: repo.root, expectedBase: base)
        }
        #expect(try repo.read("calc.py") == "x = 1\n")
    }

    @Test func applyRefusesToOverwriteDirtyFiles() async throws {
        let (repo, base, snap, _) = try await preparedPatch()
        try repo.write("calc.py", "x = 'my work in progress'\n")
        do {
            _ = try await ApplyService(git: repo.git).apply(patchFile: URL(fileURLWithPath: snap.artifact.diffPath),
                                                            changedFiles: snap.artifact.changedFiles, repoRoot: repo.root, expectedBase: base)
            Issue.record("expected destinationDirty")
        } catch let e as PatchbeamError {
            #expect(e.code == .destinationDirty)
        }
        #expect(try repo.read("calc.py") == "x = 'my work in progress'\n", "user's edit preserved")
    }

    @Test func dirtyUnrelatedFilesDoNotBlockApply() async throws {
        let (repo, base, snap, _) = try await preparedPatch()
        try repo.write("other.py", "y = 'unrelated wip'\n")
        _ = try await ApplyService(git: repo.git).apply(patchFile: URL(fileURLWithPath: snap.artifact.diffPath),
                                                        changedFiles: snap.artifact.changedFiles, repoRoot: repo.root, expectedBase: base)
        #expect(try repo.read("calc.py") == "x = 2\n")
        #expect(try repo.read("other.py") == "y = 'unrelated wip'\n")
    }

    @Test func conflictingPatchFailsClosed() async throws {
        let (repo, base, _, _) = try await preparedPatch()
        // A patch that does not match the base content.
        let bogus = FileManager.default.temporaryDirectory.appendingPathComponent("pb-bogus-\(UUID().uuidString).diff")
        try Data("""
        diff --git a/calc.py b/calc.py
        --- a/calc.py
        +++ b/calc.py
        @@ -1 +1 @@
        -x = 999
        +x = 2

        """.utf8).write(to: bogus)
        do {
            _ = try await ApplyService(git: repo.git).apply(patchFile: bogus,
                changedFiles: [ChangedFile(path: "calc.py", kind: .modified, additions: 1, deletions: 1, isBinary: false)],
                repoRoot: repo.root, expectedBase: base)
            Issue.record("expected conflict")
        } catch let e as PatchbeamError {
            #expect(e.code == .applyConflict)
        }
        #expect(try repo.read("calc.py") == "x = 1\n")
    }

    @Test func removeCleansWorktreeAndBranchWithoutTouchingSource() async throws {
        let (repo, _, _, wt) = try await preparedPatch()
        try repo.write("calc.py", "x = 'user edit'\n")
        let result = try await WorktreeManager(git: repo.git, paths: repo.paths).remove(repoRoot: repo.root, info: wt)
        #expect(result.removedWorktree && result.deletedBranch)
        #expect(!FileManager.default.fileExists(atPath: wt.path))
        #expect(try repo.read("calc.py") == "x = 'user edit'\n")
        let branches = try await repo.git.checked(["branch", "--list", "patchbeam/*"], in: repo.root)
        #expect(branches.isEmpty)
    }

    @Test func removeRefusesPathsOutsidePatchbeam() async throws {
        let repo = try await TempRepo.make()
        let foreign = WorktreeInfo(path: repo.root.path, branch: "patchbeam/x", baseCommit: try await repo.head())
        await #expect(throws: PatchbeamError.self) {
            try await WorktreeManager(git: repo.git, paths: repo.paths).remove(repoRoot: repo.root, info: foreign)
        }
        #expect(FileManager.default.fileExists(atPath: repo.root.appendingPathComponent("README.md").path))
    }

    @Test func symlinkEscapeIsDetected() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pb-sym-\(UUID().uuidString)")
        let inside = base.appendingPathComponent("inside")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = inside.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(!PathSafety.isContained(link, in: inside))
        #expect(PathSafety.isContained(inside.appendingPathComponent("a/b"), in: inside))
        #expect(!PathSafety.isContained(URL(fileURLWithPath: inside.path + "-sibling"), in: inside))
    }
}
