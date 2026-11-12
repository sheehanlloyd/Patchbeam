import Foundation

/// Capsule lifecycle states (PRD §10.1), plus `reviewReadyUnverified` for the
/// "Not verified — no check configured" / inconclusive outcome from PRD §13.
public enum CapsuleStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case ready
    case preparingWorktree
    case queued
    case running
    case awaitingApproval
    case verifying
    case reviewReadyVerified
    case reviewReadyFailed
    case reviewReadyUnverified
    case retrying
    case cancelling
    case cancelled
    case failed
    case applied
    case kept
    case discarded
    case interrupted
    case reconciling
    case resumable
    case needsRestart

    /// States in which a process or task may be live.
    public var isActive: Bool {
        switch self {
        case .preparingWorktree, .queued, .running, .awaitingApproval, .verifying, .retrying, .cancelling, .reconciling: true
        default: false
        }
    }

    public var isReviewReady: Bool {
        self == .reviewReadyVerified || self == .reviewReadyFailed || self == .reviewReadyUnverified
    }

    public var isTerminal: Bool {
        self == .applied || self == .discarded
    }

    /// Short human label; never says "verified" unless host proof exists.
    public var label: String {
        switch self {
        case .draft: "Draft"
        case .ready: "Ready to start"
        case .preparingWorktree: "Preparing worktree…"
        case .queued: "Queued"
        case .running: "Agent working…"
        case .awaitingApproval: "Needs your approval"
        case .verifying: "Running checks…"
        case .reviewReadyVerified: "Selected checks passed"
        case .reviewReadyFailed: "Needs work"
        case .reviewReadyUnverified: "Not verified"
        case .retrying: "Retrying with failure evidence…"
        case .cancelling: "Stopping…"
        case .cancelled: "Stopped"
        case .failed: "Failed"
        case .applied: "Applied to your working tree"
        case .kept: "Kept for review"
        case .discarded: "Discarded"
        case .interrupted: "Interrupted"
        case .reconciling: "Checking interrupted run…"
        case .resumable: "Can resume"
        case .needsRestart: "Interrupted — worktree preserved"
        }
    }
}

public enum CapsuleDisposition: String, Codable, Sendable {
    case applied, kept, discarded
}

/// Host-approved verification command. The argv is what runs; `display` is for UI only.
public struct VerificationRecipe: Codable, Sendable, Equatable {
    public var argv: [String]
    public var display: String
    public var timeoutSeconds: Int
    /// Set when the user explicitly approves *this exact argv*. Any change clears it.
    public var approvedArgv: [String]?
    public var approvedAt: Date?

    public init(argv: [String], display: String, timeoutSeconds: Int = 300, approvedArgv: [String]? = nil, approvedAt: Date? = nil) {
        self.argv = argv
        self.display = display
        self.timeoutSeconds = timeoutSeconds
        self.approvedArgv = approvedArgv
        self.approvedAt = approvedAt
    }

    public var isApproved: Bool { approvedArgv == argv && approvedAt != nil && !argv.isEmpty }

    public func approving(at date: Date = Date()) -> VerificationRecipe {
        var copy = self
        copy.approvedArgv = argv
        copy.approvedAt = date
        return copy
    }
}

public struct Project: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var canonicalRoot: String
    public var displayName: String
    public var recipe: VerificationRecipe?
    public var lastUsed: Date

    public init(id: UUID = UUID(), canonicalRoot: String, displayName: String, recipe: VerificationRecipe? = nil, lastUsed: Date = Date()) {
        self.id = id
        self.canonicalRoot = canonicalRoot
        self.displayName = displayName
        self.recipe = recipe
        self.lastUsed = lastUsed
    }
}

public struct ChangedFile: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable { case added, modified, deleted, renamed, copied, typeChanged, unknown }
    public var path: String
    public var oldPath: String?
    public var kind: Kind
    public var additions: Int?
    public var deletions: Int?
    public var isBinary: Bool

    public init(path: String, oldPath: String? = nil, kind: Kind, additions: Int?, deletions: Int?, isBinary: Bool) {
        self.path = path
        self.oldPath = oldPath
        self.kind = kind
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
    }
}

/// The diff from the base commit, computed by Git, with a content fingerprint.
public struct PatchArtifact: Codable, Sendable, Equatable {
    public var baseCommit: String
    public var fingerprint: String
    public var changedFiles: [ChangedFile]
    public var diffPath: String
    public var diffByteCount: Int
    public var generatedAt: Date

    public var additions: Int { changedFiles.compactMap(\.additions).reduce(0, +) }
    public var deletions: Int { changedFiles.compactMap(\.deletions).reduce(0, +) }
    public var isEmpty: Bool { changedFiles.isEmpty }

    /// e.g. "1 file · +1 −1". Only produced from Git numstat.
    public var statsLine: String {
        let n = changedFiles.count
        return "\(n) file\(n == 1 ? "" : "s") · +\(additions) −\(deletions)"
    }
}

public struct VerificationRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case baseline, patch }
    public enum Result: String, Codable, Sendable {
        case passed, failed, timedOut, cancelled, launchFailed, inconclusive
    }

    public var id: UUID
    public var capsuleID: UUID
    public var kind: Kind
    public var patchFingerprint: String?
    public var argv: [String]
    public var executablePath: String?
    public var cwd: String
    public var startedAt: Date
    public var endedAt: Date
    public var exitCode: Int32?
    public var signal: Int32?
    public var stdoutLogPath: String?
    public var stderrLogPath: String?
    public var outputTail: String
    public var parsed: ParsedTestSummary?
    public var result: Result
    public var warnings: [String]

    public var durationSeconds: Double { endedAt.timeIntervalSince(startedAt) }

    /// "Check failed (exit 1)" style summary, always grounded in the exit status.
    public var headline: String {
        switch result {
        case .passed: "Selected checks passed"
        case .failed:
            if let exitCode { "Check failed (exit \(exitCode))" } else if let signal { "Check killed by signal \(signal)" } else { "Check failed" }
        case .timedOut: "Check timed out"
        case .cancelled: "Check cancelled"
        case .launchFailed: "Check could not start"
        case .inconclusive: "Check inconclusive"
        }
    }
}

public struct ParsedTestSummary: Codable, Sendable, Equatable {
    public var framework: String
    public var total: Int?
    public var passed: Int?
    public var failed: Int?
    public var errors: Int?
    public var skipped: Int?
    public var noTestsRan: Bool

    public var line: String {
        if noTestsRan { return "No tests ran (\(framework))" }
        var parts: [String] = []
        if let total { parts.append("\(total) test\(total == 1 ? "" : "s") ran") }
        if let passed { parts.append("\(passed) passed") }
        if let failed, failed > 0 { parts.append("\(failed) failed") }
        if let errors, errors > 0 { parts.append("\(errors) errors") }
        if let skipped, skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: " · ")
    }
}

public enum ApprovalRisk: String, Codable, Sendable { case low, medium, high }

public struct ApprovalRequest: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable { case pending, allowed, denied, expired, unsupported }
    public var id: UUID
    public var capsuleID: UUID
    public var providerRequestID: String
    public var requester: String
    public var command: String?
    public var cwd: String?
    public var reason: String
    public var scope: String
    public var risk: ApprovalRisk
    public var createdAt: Date
    public var expiresAt: Date?
    public var status: Status
    public var respondedAt: Date?

    public func isExpired(now: Date = Date()) -> Bool {
        if let expiresAt { return now >= expiresAt }
        return false
    }
}

public enum ApprovalDecision: String, Codable, Sendable { case allowOnce, deny }

public struct Capsule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var projectID: UUID
    public var repoRoot: String
    public var repoDisplayName: String
    public var title: String
    public var sanitizedDiagnostic: String
    public var userGoal: String?
    public var baseCommit: String?
    public var baseBranch: String?
    public var sourceWasDirty: Bool
    public var worktreePath: String?
    public var branchName: String?
    public var providerID: String
    public var providerDisplayName: String
    public var isScriptedProvider: Bool
    public var agentSessionID: String?
    public var status: CapsuleStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var recipe: VerificationRecipe?
    public var patch: PatchArtifact?
    public var verifiedFingerprint: String?
    public var attemptCount: Int
    public var warnings: [String]
    public var lastError: PatchbeamErrorInfo?
    public var disposition: CapsuleDisposition?
    public var agentSummary: String?
    public var pendingApproval: ApprovalRequest?
    /// Exact reverse-apply command recorded after a successful apply (shown, never auto-run).
    public var rollbackCommand: [String]?
    public var baselineResult: VerificationRecord.Result?

    public static let maxAttempts = 2  // one initial attempt + one user-approved retry (PRD §6 Journey C)

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        repoRoot: String,
        repoDisplayName: String,
        title: String,
        sanitizedDiagnostic: String,
        userGoal: String? = nil,
        providerID: String,
        providerDisplayName: String,
        isScriptedProvider: Bool,
        recipe: VerificationRecipe?,
        now: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.repoRoot = repoRoot
        self.repoDisplayName = repoDisplayName
        self.title = title
        self.sanitizedDiagnostic = sanitizedDiagnostic
        self.userGoal = userGoal
        self.sourceWasDirty = false
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.isScriptedProvider = isScriptedProvider
        self.status = .draft
        self.createdAt = now
        self.updatedAt = now
        self.recipe = recipe
        self.attemptCount = 0
        self.warnings = []
    }

    public var shortID: String { String(id.uuidString.lowercased().prefix(8)) }
    public var canRetry: Bool { status == .reviewReadyFailed && attemptCount < Capsule.maxAttempts }
}

/// Serializable error snapshot for persistence and UI.
public struct PatchbeamErrorInfo: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var recovery: String?
    public var detail: String?

    public init(_ error: PatchbeamError) {
        code = error.code.rawValue
        message = error.message
        recovery = error.recovery
        detail = error.detail
    }

    public init(code: String, message: String, recovery: String? = nil, detail: String? = nil) {
        self.code = code
        self.message = message
        self.recovery = recovery
        self.detail = detail
    }
}
