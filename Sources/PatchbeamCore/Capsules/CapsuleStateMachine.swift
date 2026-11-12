import Foundation

/// Validated capsule transitions (PRD §10.1). The table is the single source of truth;
/// the orchestrator cannot move a capsule anywhere else.
public enum CapsuleStateMachine {
    public static let transitions: [CapsuleStatus: Set<CapsuleStatus>] = [
        .draft: [.ready, .discarded],
        .ready: [.preparingWorktree, .discarded],
        .preparingWorktree: [.queued, .failed, .cancelling, .interrupted],
        .queued: [.running, .failed, .cancelling, .interrupted],
        .running: [.awaitingApproval, .verifying, .reviewReadyUnverified, .failed, .cancelling, .interrupted],
        .awaitingApproval: [.running, .failed, .cancelling, .interrupted],
        .verifying: [.reviewReadyVerified, .reviewReadyFailed, .reviewReadyUnverified, .failed, .cancelling, .interrupted],
        .reviewReadyVerified: [.applied, .kept, .discarded, .verifying],
        .reviewReadyFailed: [.retrying, .kept, .discarded, .verifying],
        .reviewReadyUnverified: [.applied, .kept, .discarded, .verifying],
        .retrying: [.running, .failed, .cancelling, .interrupted],
        .cancelling: [.cancelled, .interrupted],
        .cancelled: [.kept, .discarded],
        .failed: [.kept, .discarded],
        .kept: [.discarded, .verifying],
        .applied: [],
        .discarded: [],
        .interrupted: [.reconciling],
        .reconciling: [.resumable, .needsRestart],
        .resumable: [.running, .kept, .discarded],
        .needsRestart: [.kept, .discarded],
    ]

    public static func canTransition(from: CapsuleStatus, to: CapsuleStatus) -> Bool {
        transitions[from]?.contains(to) ?? false
    }

    /// Validate and apply a transition. Entering `reviewReadyVerified` additionally requires
    /// host-owned proof: a *passing patch* verification whose fingerprint equals the
    /// capsule's current patch fingerprint. Model text can never satisfy this.
    public static func transition(
        _ capsule: inout Capsule,
        to next: CapsuleStatus,
        proof: VerificationRecord? = nil,
        now: Date = Date()
    ) throws {
        if capsule.status == next { return }  // idempotent
        guard canTransition(from: capsule.status, to: next) else {
            throw PatchbeamError(.invalidTransition, "Patchbeam blocked an invalid state change (\(capsule.status.rawValue) → \(next.rawValue)).")
        }
        if next == .reviewReadyVerified {
            guard let proof,
                  proof.capsuleID == capsule.id,
                  proof.kind == .patch,
                  proof.result == .passed,
                  proof.exitCode == 0,
                  let fp = proof.patchFingerprint,
                  let current = capsule.patch?.fingerprint,
                  fp == current
            else {
                throw PatchbeamError(.fingerprintMismatch, "Previous checks no longer match these files.", recovery: "Re-run verification.")
            }
            capsule.verifiedFingerprint = fp
        } else if next != .applied && next != .kept && next != .discarded {
            // Any other move (re-verify, retry, new edits) invalidates prior proof.
            capsule.verifiedFingerprint = nil
        }
        if next == .retrying { capsule.attemptCount += 1 }
        switch next {
        case .applied: capsule.disposition = .applied
        case .kept: capsule.disposition = .kept
        case .discarded: capsule.disposition = .discarded
        default: break
        }
        capsule.status = next
        capsule.updatedAt = now
    }
}
