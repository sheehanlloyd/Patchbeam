import Foundation
@testable import PatchbeamCore

/// Creates throwaway repositories under the temp directory. Never touches user repos.
struct TempRepo {
    let root: URL
    let git: GitClient
    let paths: AppPaths

    static func make(name: String = "repo", files: [String: String] = ["README.md": "hello\n"]) async throws -> TempRepo {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pb-git-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let root = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let git = try GitClient.locate()
        let repo = TempRepo(root: PathSafety.canonical(root), git: git,
                            paths: AppPaths(root: base.appendingPathComponent("Patchbeam Support", isDirectory: true)))
        try await git.checked(["init", "-q", "-b", "main"], in: root)
        try await git.checked(["config", "user.email", "fixture@patchbeam.invalid"], in: root)
        try await git.checked(["config", "user.name", "Patchbeam Fixture"], in: root)
        for (path, content) in files { try repo.write(path, content) }
        if !files.isEmpty { try await repo.commitAll("initial") }
        return repo
    }

    func write(_ path: String, _ content: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func commitAll(_ message: String) async throws {
        try await git.checked(["add", "-A"], in: root)
        try await git.checked(["commit", "-q", "-m", message], in: root)
    }

    func head() async throws -> String {
        try await git.checked(["rev-parse", "HEAD"], in: root)
    }
}
