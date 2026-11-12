import CryptoKit
import Foundation

/// Computes the patch between the base commit and a worktree's *current contents*
/// (tracked edits + new untracked files, honoring .gitignore) using a throwaway index,
/// so the worktree's own index is never modified.
public struct DiffService: Sendable {
    public let git: GitClient

    /// Volatile build products excluded from patches even without a .gitignore.
    public static let volatileExcludes = [
        ":(exclude,glob)**/__pycache__/**",
        ":(exclude,glob)**/*.pyc",
        ":(exclude,glob)**/.DS_Store",
        ":(exclude,glob)**/.pytest_cache/**",
    ]

    public init(git: GitClient) {
        self.git = git
    }

    public struct Snapshot: Sendable {
        public var artifact: PatchArtifact
        public var diff: Data
    }

    /// - Parameter outputDirectory: where the `.diff` file is written (capsule folder).
    public func snapshot(worktree: URL, baseCommit: String, outputDirectory: URL) async throws -> Snapshot {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let index = outputDirectory.appendingPathComponent(".pb-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: index) }
        let env = ["GIT_INDEX_FILE": index.path]

        try await git.checked(["read-tree", "HEAD"], in: worktree, environment: env)
        try await git.checked(["add", "-A", "--", "."] + Self.volatileExcludes, in: worktree, environment: env)

        let common = ["diff", "--cached", "--find-renames", "--no-ext-diff", "--no-textconv"]
        let diffResult = try await git.run(common + ["--binary", baseCommit], in: worktree, environment: env)
        guard diffResult.succeeded, !diffResult.stdoutTruncated else {
            throw PatchbeamError(.gitCommandFailed, "Couldn't compute the patch.", detail: diffResult.stderrString)
        }
        let numstat = try await git.checked(common + ["--numstat", "-z", baseCommit], in: worktree, environment: env)
        let nameStatus = try await git.checked(common + ["--name-status", "-z", baseCommit], in: worktree, environment: env)

        let files = Self.parse(nameStatus: nameStatus, numstat: numstat)
        let diff = diffResult.stdout
        let fingerprint = Self.fingerprint(diff)
        let diffURL = outputDirectory.appendingPathComponent("patch-\(fingerprint.prefix(12)).diff")
        try diff.write(to: diffURL, options: .atomic)
        let artifact = PatchArtifact(
            baseCommit: baseCommit,
            fingerprint: fingerprint,
            changedFiles: files,
            diffPath: diffURL.path,
            diffByteCount: diff.count,
            generatedAt: Date()
        )
        return Snapshot(artifact: artifact, diff: diff)
    }

    public static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func parse(nameStatus: String, numstat: String) -> [ChangedFile] {
        // numstat -z: "add\tdel\tpath\0" or, for renames, "add\tdel\t\0old\0new\0".
        var counts: [String: (Int?, Int?, Bool)] = [:]
        var ns = numstat.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        while let head = ns.popFirst() {
            if head.isEmpty { continue }
            let parts = head.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            var path = parts[2]
            if path.isEmpty {  // rename form
                _ = ns.popFirst()
                path = ns.popFirst() ?? ""
            }
            let binary = parts[0] == "-" && parts[1] == "-"
            counts[path] = (Int(parts[0]), Int(parts[1]), binary)
        }

        var files: [ChangedFile] = []
        var tokens = nameStatus.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let status = tokens.popFirst() {
            guard let letter = status.first else { continue }
            var oldPath: String?
            var path: String
            if letter == "R" || letter == "C" {
                oldPath = tokens.popFirst()
                path = tokens.popFirst() ?? ""
            } else {
                path = tokens.popFirst() ?? ""
            }
            let kind: ChangedFile.Kind = switch letter {
            case "A": .added
            case "M": .modified
            case "D": .deleted
            case "R": .renamed
            case "C": .copied
            case "T": .typeChanged
            default: .unknown
            }
            let c = counts[path]
            files.append(ChangedFile(path: path, oldPath: oldPath, kind: kind, additions: c?.0, deletions: c?.1, isBinary: c?.2 ?? false))
        }
        return files
    }
}
