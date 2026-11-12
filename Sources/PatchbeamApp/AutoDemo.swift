import AppKit
import PatchbeamCore

/// `--autodemo`: drives the real app through the golden path on a freshly generated fixture,
/// calling exactly the `AppModel` methods the buttons call (open, demo, approve check, start,
/// switch tabs, apply → confirm). Used to record authentic media and as a GUI smoke test.
/// It uses the scripted DemoAgent (no model) and is labeled as such in every frame.
@MainActor
enum AutoDemo {
    static func run(model: AppModel, recorder: EvidenceRecorder?, geometry: @escaping () -> String = { "" }, log: @escaping (String) -> Void) async {
        // PATCHBEAM_AUTODEMO_PACE stretches only the *pauses between UI steps* (for a readable
        // walkthrough); the repair itself always runs at its real speed.
        let pace = Double(ProcessInfo.processInfo.environment["PATCHBEAM_AUTODEMO_PACE"] ?? "") ?? 1
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s * pace)) }
        func shot(_ name: String) {
            recorder?.still(name)
            let g = geometry()
            recorder?.note("\(name): \(g)")
            log("still \(name) | \(g)")
        }

        recorder?.start()
        log("autodemo: dormant")
        await pause(1.2)
        shot("01-dormant")

        model.presentation = .glance
        await pause(1.2)
        shot("02-glance-empty")

        await model.prepareDemo()
        await pause(1.0)
        shot("03-intake-demo")
        model.intake.checkApproved = true
        await pause(1.2)
        shot("04-intake-approved")

        log("autodemo: start repair")
        await model.startRepair()
        guard let id = model.selected?.id else { log("autodemo: FAILED to start: \(model.message?.title ?? "?")"); recorder?.stop(); return }

        var sawRunning = false
        for _ in 0..<600 {
            await pause(0.1)
            guard let c = model.capsules.first(where: { $0.id == id }) else { continue }
            if c.status == .running && !sawRunning { sawRunning = true; await pause(0.6); shot("05-running") }
            if c.status.isReviewReady || c.status == .failed { break }
        }
        await pause(1.0)
        let status = model.capsules.first { $0.id == id }?.status
        log("autodemo: review status \(status?.rawValue ?? "nil")")
        model.tab = .activity
        await pause(1.4)
        shot("06-review-activity")
        model.tab = .changes
        await pause(1.8)
        shot("07-review-changes")
        model.tab = .proof
        await pause(2.0)
        shot("08-review-proof")

        if status == .reviewReadyVerified, let c = model.selected {
            model.requestApply(c)
            await pause(1.6)
            shot("09-apply-confirm")
            model.confirm()
            for _ in 0..<100 {
                await pause(0.1)
                if model.capsules.first(where: { $0.id == id })?.status == .applied { break }
            }
            await pause(1.4)
            shot("10-applied")
        }
        model.message = nil
        model.collapse()
        await pause(1.0)
        model.presentation = .glance
        await pause(1.4)
        shot("11-glance-done")
        model.collapse()
        await pause(0.8)
        recorder?.stop()
        log("autodemo: done status=\(model.capsules.first { $0.id == id }?.status.rawValue ?? "nil")")
    }
}
