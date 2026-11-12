import Foundation

/// Strips terminal escape sequences and control characters before anything is rendered
/// or sent to a provider (PRD §14.2).
public enum TerminalTextSanitizer {
    public static func sanitize(_ input: String) -> String {
        var out = String.UnicodeScalarView()
        var scalars = Array(input.unicodeScalars)
        // Normalize CRLF / lone CR.
        var i = 0
        let count = scalars.count
        while i < count {
            let s = scalars[i]
            switch s.value {
            case 0x1B:  // ESC
                i += 1
                guard i < count else { break }
                let next = scalars[i].value
                if next == 0x5B {  // CSI: ESC [ params final(0x40–0x7E)
                    i += 1
                    while i < count, !(0x40...0x7E).contains(scalars[i].value) { i += 1 }
                    i += 1
                } else if next == 0x5D || next == 0x50 || next == 0x5F || next == 0x5E {  // OSC / DCS / APC / PM: until BEL or ST
                    i += 1
                    while i < count {
                        if scalars[i].value == 0x07 { i += 1; break }
                        if scalars[i].value == 0x1B, i + 1 < count, scalars[i + 1].value == 0x5C { i += 2; break }
                        i += 1
                    }
                } else {
                    i += 1  // two-char escape
                }
                continue
            case 0x9B:  // 8-bit CSI
                i += 1
                while i < count, !(0x40...0x7E).contains(scalars[i].value) { i += 1 }
                i += 1
                continue
            case 0x0D:  // CR → newline (CRLF collapses to one)
                if i + 1 < count, scalars[i + 1].value == 0x0A { i += 1 }
                out.append("\n")
            case 0x09, 0x0A:
                out.append(s)
            case 0x00...0x1F, 0x7F, 0x80...0x9F:
                break  // drop other C0/C1 controls (incl. backspace tricks)
            case 0x202A...0x202E, 0x2066...0x2069:
                break  // bidi overrides can disguise text
            default:
                out.append(s)
            }
            i += 1
        }
        scalars.removeAll()
        return String(out)
    }
}

public struct SecretFinding: Sendable, Equatable, Hashable {
    public var kind: String
    public var range: Range<String.Index>
    public var preview: String

    public static func == (a: SecretFinding, b: SecretFinding) -> Bool { a.kind == b.kind && a.range == b.range }
    public func hash(into hasher: inout Hasher) { hasher.combine(kind) }
}

/// Fallible local regex/entropy hints for secrets and personal data. The UI tells users
/// it can miss things (PRD §14.2).
public struct SecretScanner: Sendable {
    public struct Rule: Sendable {
        public var kind: String
        public var pattern: String
        /// Capture group to redact (0 = whole match).
        public var group: Int
    }

    public static let defaultRules: [Rule] = [
        Rule(kind: "private-key", pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, group: 0),
        Rule(kind: "anthropic-key", pattern: #"sk-ant-[A-Za-z0-9_\-]{20,}"#, group: 0),
        Rule(kind: "openai-key", pattern: #"sk-(?:proj-)?[A-Za-z0-9_\-]{20,}"#, group: 0),
        Rule(kind: "github-token", pattern: #"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b"#, group: 0),
        Rule(kind: "aws-access-key", pattern: #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#, group: 0),
        Rule(kind: "slack-token", pattern: #"\bxox[abposr]-[A-Za-z0-9-]{10,}\b"#, group: 0),
        Rule(kind: "jwt", pattern: #"\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b"#, group: 0),
        Rule(kind: "bearer-token", pattern: #"(?i)\bauthorization\s*:\s*(?:bearer|basic|token)\s+([A-Za-z0-9._~+/=\-]{8,})"#, group: 1),
        Rule(kind: "credential-assignment", pattern: #"(?i)\b(?:api[_-]?key|secret|token|password|passwd|pwd)\b\s*[:=]\s*["']?([^\s"',;]{6,})"#, group: 1),
        Rule(kind: "url-credentials", pattern: #"\b[a-zA-Z][a-zA-Z0-9+.\-]{0,15}://[^\s/:@]{1,128}:([^\s/@]{1,256})@"#, group: 1),
        Rule(kind: "email", pattern: #"\b[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9.\-]{1,190}\.[A-Za-z]{2,24}\b"#, group: 0),
    ]

    public var rules: [Rule]

    public init(rules: [Rule] = SecretScanner.defaultRules) {
        self.rules = rules
    }

    public func scan(_ text: String) -> [SecretFinding] {
        var findings: [SecretFinding] = []
        let ns = text as NSString
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let r = match.range(at: rule.group)
                guard r.location != NSNotFound, let range = Range(r, in: text) else { continue }
                // Skip ranges already covered by an earlier (more specific) rule.
                if findings.contains(where: { $0.range.overlaps(range) }) { continue }
                let value = String(text[range])
                let preview = value.count <= 8 ? String(repeating: "•", count: value.count) : value.prefix(4) + "…" + value.suffix(2)
                findings.append(SecretFinding(kind: rule.kind, range: range, preview: String(preview)))
            }
        }
        return findings.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    public func redact(_ text: String, findings: [SecretFinding]? = nil) -> String {
        let found = (findings ?? scan(text)).sorted { $0.range.lowerBound > $1.range.lowerBound }
        var result = text
        for f in found {
            result.replaceSubrange(f.range, with: "[REDACTED:\(f.kind)]")
        }
        return result
    }
}

/// A prepared diagnostic shown to the user for review before it can be sent (PRD §6 A.3).
public struct DiagnosticDraft: Sendable, Equatable {
    public var text: String
    public var sourceName: String?
    public var originalByteCount: Int
    public var truncated: Bool
    public var findings: [String]  // finding kinds, for the preview badge

    public var byteCount: Int { text.utf8.count }
    public var lineCount: Int { text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count }

    public func previewLines(_ n: Int = 6) -> [String] {
        Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(n).map(String.init))
    }
}

public enum DiagnosticIntake {
    /// Upper bound kept for a diagnostic (head + tail are kept when larger).
    public static let maxBytes = 200_000
    /// Files above this size are rejected outright rather than read.
    public static let maxFileBytes = 20_000_000
    public static let acceptedExtensions: Set<String> = ["log", "txt", "out", "err", "trace", ""]

    public static func fromText(_ raw: String, sourceName: String? = nil, scanner: SecretScanner = SecretScanner()) throws -> DiagnosticDraft {
        let originalBytes = raw.utf8.count
        var text = TerminalTextSanitizer.sanitize(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PatchbeamError(.diagnosticEmpty, "Paste an error, stack trace or failing test output first.")
        }
        var truncated = false
        if text.utf8.count > maxBytes {
            // Keep the head (command, first error) and the tail (final summary) of huge logs.
            let headBudget = maxBytes * 2 / 5
            let tailBudget = maxBytes - headBudget - 100
            let head = String(decoding: Data(text.utf8).prefix(headBudget), as: UTF8.self)
            let tail = String(decoding: Data(text.utf8).suffix(tailBudget), as: UTF8.self)
            text = head + "\n\n[… \(originalBytes - maxBytes) bytes omitted by Patchbeam …]\n\n" + tail
            truncated = true
        }
        let findings = scanner.scan(text).map(\.kind)
        return DiagnosticDraft(text: text, sourceName: sourceName, originalByteCount: originalBytes, truncated: truncated, findings: findings)
    }

    public static func fromFile(_ url: URL, scanner: SecretScanner = SecretScanner()) throws -> DiagnosticDraft {
        let ext = url.pathExtension.lowercased()
        guard acceptedExtensions.contains(ext) else {
            throw PatchbeamError(.diagnosticBinary, "Patchbeam reads text logs (.log, .txt). “\(url.lastPathComponent)” isn't one.")
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxFileBytes else {
            throw PatchbeamError(.diagnosticTooLarge, "That log is \(size / 1_000_000) MB. Trim it to the failing section and try again.")
        }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw PatchbeamError(.notFound, "Couldn't read “\(url.lastPathComponent)”.")
        }
        guard !data.isEmpty else {
            throw PatchbeamError(.diagnosticEmpty, "“\(url.lastPathComponent)” is empty.")
        }
        if data.prefix(8192).contains(0) {
            throw PatchbeamError(.diagnosticBinary, "“\(url.lastPathComponent)” looks like a binary file, not a text log.")
        }
        return try fromText(String(decoding: data, as: UTF8.self), sourceName: url.lastPathComponent, scanner: scanner)
    }

    /// Best short title: the last exception/assertion line, else the first non-empty line.
    public static func inferTitle(_ text: String) -> String {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let patterns = ["Error:", "Error ", "Exception", "FAILED", "FAIL ", "error:", "panic:", "fatal:"]
        let candidate = lines.last { line in patterns.contains { line.contains($0) } } ?? lines.first ?? "Untitled diagnostic"
        return candidate.count > 90 ? String(candidate.prefix(89)) + "…" : candidate
    }

    /// Absolute file paths mentioned in a traceback (Python, Node, Swift, Go styles). Used
    /// only to *suggest* a previously approved repository, never to open anything.
    public static func referencedPaths(_ text: String) -> [String] {
        let pattern = #"(/(?:[^\s"'():,]+/)+[^\s"'():,]+\.[A-Za-z0-9]{1,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var seen: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let p = ns.substring(with: m.range(at: 1))
            if !seen.contains(p) { seen.append(p) }
        }
        return seen
    }

    /// Suggest a known project only when a referenced path lies inside exactly one root.
    public static func suggestProject(for text: String, among projects: [Project]) -> Project? {
        let paths = referencedPaths(text)
        let matches = projects.filter { project in
            paths.contains { $0 == project.canonicalRoot || $0.hasPrefix(project.canonicalRoot + "/") }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
