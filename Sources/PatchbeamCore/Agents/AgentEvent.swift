import Foundation

/// Normalized, versioned agent event protocol (PRD §10.3). Every provider adapter
/// converts its native stream into these.
public struct AgentEvent: Codable, Sendable, Equatable, Identifiable {
    public static let schema = 1

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case sessionStarted = "session_started"
        case thinking
        case toolProposed = "tool_proposed"
        case approvalRequested = "approval_requested"
        case toolStarted = "tool_started"
        case toolFinished = "tool_finished"
        case editObserved = "edit_observed"
        case message
        case completed
        case failed
        case cancelled
        case heartbeat
        /// Host-generated lifecycle notes (worktree created, verification started…).
        case host
    }

    public enum Phase: String, Codable, Sendable {
        case preparing, diagnosing, editing, verifying, reviewing, done
    }

    public var schema: Int
    public var capsuleID: UUID
    public var sequence: Int
    public var timestamp: Date
    public var kind: Kind
    public var phase: Phase
    public var summary: String
    /// Provider's own ID when available (used to drop duplicates).
    public var providerEventID: String?
    /// Small redacted metadata only (exit codes, durations, file names). Never prompts or secrets.
    public var metadata: [String: String]

    public var id: String { "\(capsuleID.uuidString)#\(sequence)" }

    public init(
        capsuleID: UUID,
        sequence: Int = 0,
        timestamp: Date = Date(),
        kind: Kind,
        phase: Phase,
        summary: String,
        providerEventID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.schema = AgentEvent.schema
        self.capsuleID = capsuleID
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.phase = phase
        self.summary = summary
        self.providerEventID = providerEventID
        self.metadata = metadata
    }
}

/// Assigns monotonic sequence numbers and drops duplicate provider events, so replays or
/// reconnects never produce duplicate UI actions.
public struct EventSequencer: Sendable {
    private var next: Int
    private var seenProviderIDs: Set<String> = []

    public init(startingAt next: Int = 1) {
        self.next = next
    }

    public mutating func accept(_ event: AgentEvent) -> AgentEvent? {
        if let pid = event.providerEventID {
            guard seenProviderIDs.insert(pid).inserted else { return nil }
        }
        var e = event
        e.sequence = next
        next += 1
        return e
    }
}
