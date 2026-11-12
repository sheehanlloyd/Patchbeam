import AppKit
import PatchbeamCore
import SwiftUI

struct ActivityList: View {
    var events: [AgentEvent]
    var capsule: Capsule

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if events.isEmpty {
                        Text("No activity yet.").font(.system(size: 12)).foregroundStyle(Theme.textSubdued).padding(.top, 20)
                    }
                    ForEach(events.suffix(400)) { e in
                        EventRow(event: e).id(e.id)
                    }
                    if let summary = capsule.agentSummary, !capsule.status.isActive {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Agent's summary (model text, not proof)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textSubdued)
                            Text(summary).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: events.count) { _, _ in
                if let last = events.last { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .accessibilityLabel("Activity log")
    }
}

struct EventRow: View {
    var event: AgentEvent

    private var symbol: (String, Color) {
        switch event.kind {
        case .host: ("server.rack", Theme.accent)
        case .sessionStarted: ("play.circle", Theme.executing)
        case .thinking: ("ellipsis.bubble", Theme.textSubdued)
        case .toolProposed, .toolStarted: ("wrench.and.screwdriver", Theme.executing)
        case .toolFinished: (event.metadata["status"] == "error" ? "exclamationmark.circle" : "checkmark.circle", event.metadata["status"] == "error" ? Theme.failed : Theme.textSecondary)
        case .editObserved: ("pencil.line", Theme.ready)
        case .approvalRequested: ("hand.raised", Theme.warning)
        case .message: (event.metadata["approvalUnsupported"] == "true" ? "lock" : "text.bubble", event.metadata["approvalUnsupported"] == "true" ? Theme.warning : Theme.textSecondary)
        case .completed: ("flag.checkered", Theme.textSecondary)
        case .failed: ("xmark.octagon", Theme.failed)
        case .cancelled: ("stop.circle", Theme.textSecondary)
        case .heartbeat: ("waveform.path", Theme.textSubdued)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol.0).foregroundStyle(symbol.1).font(.system(size: 10.5)).frame(width: 14)
            Text(event.summary).font(.system(size: 11.5)).foregroundStyle(event.kind == .host ? Theme.text : Theme.textSecondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(event.timestamp, format: .dateTime.hour().minute().second()).font(Theme.mono(9.5)).foregroundStyle(Theme.textSubdued)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.kind == .host ? "Patchbeam" : "Agent"): \(event.summary)")
    }
}

/// Unified diff from Git, rendered as selectable monospaced text. Large diffs show a bounded
/// prefix plus an explicit "open full diff" fallback, never silent truncation (PRD §12.4).
struct ChangesView: View {
    var model: AppModel
    var capsule: Capsule
    @State private var diff: DiffDocument?

    static let maxLines = 1500

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let patch = capsule.patch, !patch.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(patch.changedFiles, id: \.self) { f in
                            Chip(text: fileLabel(f), symbol: icon(f.kind), tint: f.kind == .deleted ? Theme.failed : f.kind == .added ? Theme.ready : Theme.textSecondary, mono: true)
                        }
                    }
                }
                GeometryReader { viewport in
                    ScrollView([.vertical, .horizontal]) {
                        Group {
                            if let diff {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(diff.lines.prefix(Self.maxLines)) { line in
                                        Text(line.text.isEmpty ? " " : line.text)
                                            .font(Theme.mono(11))
                                            .foregroundStyle(line.color)
                                            .fixedSize()
                                            .padding(.horizontal, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(line.background)
                                    }
                                }
                                .textSelection(.enabled)
                                .padding(.vertical, 6)
                            } else {
                                ProgressView().controlSize(.small).padding()
                            }
                        }
                        // Pin to the top-leading corner; a 2D ScrollView otherwise centers content.
                        .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .topLeading)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
                if let diff, diff.lines.count > Self.maxLines {
                    Button("Diff has \(diff.lines.count) lines — open the full diff file") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: patch.diffPath))
                    }
                    .buttonStyle(PanelButtonStyle(kind: .quiet))
                }
            } else if capsule.status.isActive {
                Text("Changes appear here when the agent finishes.").font(.system(size: 12)).foregroundStyle(Theme.textSubdued).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No changes.").font(.system(size: 12)).foregroundStyle(Theme.textSubdued).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: capsule.patch?.fingerprint) { await load() }
        .accessibilityLabel("Changes")
    }

    private func load() async {
        guard let path = capsule.patch?.diffPath else { diff = nil; return }
        let doc = await Task.detached { DiffDocument(path: path) }.value
        diff = doc
    }

    private func fileLabel(_ f: ChangedFile) -> String {
        let counts = f.isBinary ? "binary" : "+\(f.additions ?? 0) −\(f.deletions ?? 0)"
        if let old = f.oldPath { return "\(old) → \(f.path) \(counts)" }
        return "\(f.path) \(counts)"
    }

    private func icon(_ k: ChangedFile.Kind) -> String {
        switch k {
        case .added: "plus.square"
        case .deleted: "minus.square"
        case .renamed, .copied: "arrow.right.square"
        default: "square.and.pencil"
        }
    }
}

struct DiffDocument: Sendable {
    struct Line: Identifiable, Sendable {
        let id: Int
        let text: String
        let kind: Kind
        enum Kind: Sendable { case add, del, hunk, meta, context }

        var color: Color {
            switch kind {
            case .add: Theme.ready
            case .del: Theme.failed
            case .hunk: Theme.accent
            case .meta: Theme.textSubdued
            case .context: Theme.textSecondary
            }
        }

        var background: Color {
            switch kind {
            case .add: Theme.ready.opacity(0.08)
            case .del: Theme.failed.opacity(0.08)
            default: .clear
            }
        }
    }

    let lines: [Line]

    init(path: String) {
        let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let clean = TerminalTextSanitizer.sanitize(raw)
        lines = clean.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { i, s in
            let str = String(s)
            let kind: Line.Kind =
                str.hasPrefix("+++") || str.hasPrefix("---") || str.hasPrefix("diff --git") || str.hasPrefix("index ") || str.hasPrefix("GIT binary") ? .meta
                : str.hasPrefix("@@") ? .hunk
                : str.hasPrefix("+") ? .add
                : str.hasPrefix("-") ? .del
                : .context
            return Line(id: i, text: str, kind: kind)
        }
    }
}

/// Host-owned proof. "Selected checks passed" only from a recorded exit code 0 for the current
/// patch fingerprint; red-before evidence shown when the baseline ran.
struct ProofView: View {
    var model: AppModel
    var capsule: Capsule

    var body: some View {
        // Latest patch proof first, then the red-before baseline.
        let all = model.verifications[capsule.id] ?? []
        let records = all.filter { $0.kind == .patch }.reversed() + all.filter { $0.kind == .baseline }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if records.isEmpty {
                    Text(capsule.recipe == nil ? "Not verified — no check configured." : "No checks have run yet.")
                        .font(.system(size: 12)).foregroundStyle(capsule.recipe == nil ? Theme.warning : Theme.textSubdued).padding(.top, 16)
                }
                ForEach(records) { r in ProofCard(record: r, current: r.patchFingerprint == capsule.patch?.fingerprint, capsule: capsule) }
                if capsule.status == .reviewReadyVerified {
                    Text("Passing selected checks doesn't prove the fix is complete. Review the diff.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textSubdued)
                }
            }
        }
        .accessibilityLabel("Proof")
    }
}

struct ProofCard: View {
    var record: VerificationRecord
    var current: Bool
    var capsule: Capsule
    @State private var hovering = false

    private var tint: Color {
        switch record.result {
        case .passed: current ? Theme.ready : Theme.textSecondary
        case .failed, .timedOut, .launchFailed: record.kind == .baseline ? Theme.warning : Theme.failed
        case .inconclusive, .cancelled: Theme.warning
        }
    }

    private var icon: String {
        switch record.result {
        case .passed: "checkmark.circle.fill"
        case .failed, .timedOut, .launchFailed: "xmark.circle.fill"
        default: "exclamationmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                Text(record.kind == .baseline ? "Before (base \(capsule.baseCommit.map { String($0.prefix(7)) } ?? ""))" : "After (patch)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Text(record.headline).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                Spacer()
                if record.kind == .patch && !current {
                    Chip(text: "stale — files changed", symbol: "clock.arrow.circlepath", tint: Theme.warning)
                }
            }
            Text("$ \(record.argv.joined(separator: " "))").font(Theme.mono(11)).foregroundStyle(Theme.text).textSelection(.enabled)
            HStack(spacing: 10) {
                Text("exit \(record.exitCode.map(String.init) ?? (record.signal.map { "signal \($0)" } ?? "—"))")
                Text(String(format: "%.2fs", record.durationSeconds))
                if let p = record.parsed { Text(p.line) }
                Text(record.endedAt, format: .dateTime.hour().minute().second())
            }
            .font(Theme.mono(10.5)).foregroundStyle(Theme.textSubdued)
            ForEach(record.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.warning)
            }
            if record.result != .passed || record.kind == .baseline {
                Text(failureExcerpt).font(Theme.mono(10.5)).foregroundStyle(Theme.textSecondary).textSelection(.enabled).lineLimit(10)
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.background))
                    .overlay(alignment: .topTrailing) {
                        if hovering {
                            Button("Copy failure") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.outputTail, forType: .string)
                            }
                            .buttonStyle(PanelButtonStyle(kind: .secondary)).controlSize(.mini).padding(4)
                        }
                    }
            }
            HStack {
                if let p = record.stderrLogPath {
                    Button("stderr log") { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }.buttonStyle(.link)
                }
                if let p = record.stdoutLogPath {
                    Button("stdout log") { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }.buttonStyle(.link)
                }
            }
            .font(.system(size: 10.5))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(record.kind == .baseline ? "Baseline" : "Patch") check: \(record.headline), exit code \(record.exitCode.map(String.init) ?? "none")")
    }

    private var failureExcerpt: String {
        let lines = record.outputTail.split(separator: "\n", omittingEmptySubsequences: false)
        if let i = lines.firstIndex(where: { $0.contains("Error") || $0.contains("FAIL") }) {
            return lines[max(0, i - 2)...].prefix(10).joined(separator: "\n")
        }
        return lines.suffix(8).joined(separator: "\n")
    }
}
