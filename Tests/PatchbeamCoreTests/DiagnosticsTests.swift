import Foundation
import Testing
@testable import PatchbeamCore

@Suite("Diagnostics intake")
struct DiagnosticsTests {
    @Test func stripsAnsiAndControlSequences() {
        let raw = "\u{1B}[31mFAILED\u{1B}[0m test\r\n\u{1B}]0;evil title\u{07}next\u{08}\u{08}line\u{202E}txt"
        #expect(TerminalTextSanitizer.sanitize(raw) == "FAILED test\nnextlinetxt")
    }

    @Test func keepsUnicodeAndTabs() {
        let raw = "Fehler: ünïcödé ✓ 日本語\tcol\nسطر"
        #expect(TerminalTextSanitizer.sanitize(raw) == raw)
    }

    @Test func emptyDiagnosticIsRejectedWithActionableCopy() {
        #expect(throws: PatchbeamError.self) { try DiagnosticIntake.fromText("  \n\u{1B}[0m \n") }
    }

    @Test func hugeDiagnosticKeepsHeadAndTail() throws {
        let raw = "HEAD-MARKER\n" + String(repeating: "x", count: 300_000) + "\nTAIL-MARKER"
        let d = try DiagnosticIntake.fromText(raw)
        #expect(d.truncated)
        #expect(d.byteCount <= DiagnosticIntake.maxBytes + 200)
        #expect(d.text.hasPrefix("HEAD-MARKER"))
        #expect(d.text.hasSuffix("TAIL-MARKER"))
        #expect(d.text.contains("bytes omitted by Patchbeam"))
    }

    @Test func detectsAndRedactsCommonSecrets() {
        let text = """
        Authorization: Bearer abcdefghijklmnop1234
        OPENAI_API_KEY=sk-proj-AAAAAAAAAAAAAAAAAAAAAAAAAA
        token = ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789
        aws AKIAABCDEFGHIJKLMNOP
        contact dev@example.com
        db postgres://admin:hunter22@db.local/app
        """
        let scanner = SecretScanner()
        let kinds = Set(scanner.scan(text).map(\.kind))
        #expect(kinds.isSuperset(of: ["bearer-token", "openai-key", "github-token", "aws-access-key", "email", "url-credentials"]))
        let redacted = scanner.redact(text)
        for secret in ["abcdefghijklmnop1234", "sk-proj-AAAA", "ghp_ABCDEF", "AKIAABCDEFGHIJKLMNOP", "dev@example.com", "hunter22"] {
            #expect(!redacted.contains(secret), "\(secret) leaked")
        }
        #expect(redacted.contains("[REDACTED:"))
    }

    /// Regression: unbounded quantifiers made scanning a 200 KB unbroken log take ~4 minutes.
    @Test func scanningAdversarialLogIsFast() {
        let hostile = String(repeating: "a", count: 200_000) + String(repeating: "x://", count: 10_000)
        let start = Date()
        _ = SecretScanner().scan(hostile)
        #expect(Date().timeIntervalSince(start) < 2.0)
    }

    @Test func ordinaryTracebackHasNoFalsePositives() {
        let trace = """
        Traceback (most recent call last):
          File "/Users/dev/shop/test_calculator.py", line 9, in test_total_adds_tax
            self.assertEqual(total([10.0, 20.0], tax_rate=0.1), 33.0)
        AssertionError: 27.0 != 33.0
        """
        #expect(SecretScanner().scan(trace).isEmpty)
    }

    @Test func infersTitleFromLastErrorLine() {
        let trace = "Traceback...\n  File \"x.py\"\nAssertionError: 27.0 != 33.0\n"
        #expect(DiagnosticIntake.inferTitle(trace) == "AssertionError: 27.0 != 33.0")
    }

    @Test func suggestsProjectOnlyWhenUnambiguous() {
        let a = Project(canonicalRoot: "/Users/dev/shop", displayName: "shop")
        let b = Project(canonicalRoot: "/Users/dev/other", displayName: "other")
        let trace = "File \"/Users/dev/shop/test_calculator.py\", line 9"
        #expect(DiagnosticIntake.suggestProject(for: trace, among: [a, b])?.displayName == "shop")
        #expect(DiagnosticIntake.suggestProject(for: "no paths here", among: [a, b]) == nil)
        // A prefix-similar root must not match ("/Users/dev/shopping").
        let c = Project(canonicalRoot: "/Users/dev/sho", displayName: "sho")
        #expect(DiagnosticIntake.suggestProject(for: trace, among: [c]) == nil)
    }

    @Test func fileIntakeRejectsBinaryEmptyAndUnsupported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pb-diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let empty = dir.appendingPathComponent("empty.log")
        try Data().write(to: empty)
        let binary = dir.appendingPathComponent("bin.log")
        try Data([0x41, 0x00, 0x42]).write(to: binary)
        let image = dir.appendingPathComponent("shot.png")
        try Data("x".utf8).write(to: image)
        let good = dir.appendingPathComponent("pytest output.log")
        try Data("\u{1B}[31mE   AssertionError\u{1B}[0m".utf8).write(to: good)

        #expect(throws: PatchbeamError.self) { try DiagnosticIntake.fromFile(empty) }
        #expect(throws: PatchbeamError.self) { try DiagnosticIntake.fromFile(binary) }
        #expect(throws: PatchbeamError.self) { try DiagnosticIntake.fromFile(image) }
        let d = try DiagnosticIntake.fromFile(good)
        #expect(d.text == "E   AssertionError")
        #expect(d.sourceName == "pytest output.log")
    }
}
