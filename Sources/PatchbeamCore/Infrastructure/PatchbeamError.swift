import Foundation

/// Typed domain error with a user-facing message, stable diagnostic code and optional
/// recovery hint (PRD §15). The copy here follows PRD §9 / §23, so it is never just
/// "Unknown error".
public struct PatchbeamError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, Codable {
        case gitMissing = "PB-GIT-MISSING"
        case notGitRepository = "PB-GIT-NOREPO"
        case unbornHead = "PB-GIT-NOHEAD"
        case worktreeFailed = "PB-GIT-WORKTREE"
        case gitCommandFailed = "PB-GIT-CMD"
        case destinationMoved = "PB-APPLY-MOVED"
        case destinationDirty = "PB-APPLY-DIRTY"
        case applyConflict = "PB-APPLY-CONFLICT"
        case applyInProgress = "PB-APPLY-BUSY"
        case fingerprintMismatch = "PB-PROOF-STALE"
        case invalidTransition = "PB-STATE"
        case providerMissing = "PB-AGENT-MISSING"
        case providerUnauthenticated = "PB-AGENT-AUTH"
        case providerFailed = "PB-AGENT-FAILED"
        case approvalUnsupported = "PB-AGENT-NOAPPROVE"
        case approvalStale = "PB-AGENT-STALE"
        case commandRequired = "PB-CHECK-EMPTY"
        case commandUnsupportedSyntax = "PB-CHECK-SYNTAX"
        case commandNotFound = "PB-CHECK-NOTFOUND"
        case commandNotApproved = "PB-CHECK-UNAPPROVED"
        case diagnosticEmpty = "PB-DIAG-EMPTY"
        case diagnosticBinary = "PB-DIAG-BINARY"
        case diagnosticTooLarge = "PB-DIAG-LARGE"
        case pathEscape = "PB-PATH-ESCAPE"
        case persistence = "PB-DB"
        case retryLimit = "PB-RETRY-LIMIT"
        case noChanges = "PB-AGENT-NOCHANGE"
        case diskSpace = "PB-DISK"
        case notFound = "PB-NOTFOUND"
    }

    public var code: Code
    public var message: String
    public var recovery: String?
    public var detail: String?

    public init(_ code: Code, _ message: String, recovery: String? = nil, detail: String? = nil) {
        self.code = code
        self.message = message
        self.recovery = recovery
        self.detail = detail
    }

    public var description: String {
        var parts = ["[\(code.rawValue)] \(message)"]
        if let recovery { parts.append(recovery) }
        if let detail, !detail.isEmpty { parts.append("Detail: \(detail)") }
        return parts.joined(separator: " — ")
    }
}
