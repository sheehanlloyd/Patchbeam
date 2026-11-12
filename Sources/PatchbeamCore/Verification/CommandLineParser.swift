import Foundation

/// Turns a user-typed check like `python3 -m unittest -v` into an argv array with POSIX-like
/// quoting, but **no** shell features: no pipes, redirects, variables, substitution, globbing
/// or chaining. Anything that would need a shell is rejected rather than reinterpreted.
public enum CommandLineParser {
    static let forbidden: Set<Character> = ["|", "&", ";", "<", ">", "$", "`", "(", ")", "*", "{", "}"]

    public static func parse(_ input: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var inToken = false
        var quote: Character?
        var iterator = input.makeIterator()
        while let ch = iterator.next() {
            if let q = quote {
                if ch == q {
                    quote = nil
                } else if ch == "\\" && q == "\"" {
                    guard let next = iterator.next() else { break }
                    if next == "$" || next == "`" || next == "\"" || next == "\\" { current.append(next) } else { current.append("\\"); current.append(next) }
                } else if q == "\"" && (ch == "$" || ch == "`") {
                    throw unsupported(ch)
                } else {
                    current.append(ch)
                }
                continue
            }
            switch ch {
            case " ", "\t":
                if inToken { args.append(current); current = ""; inToken = false }
            case "\n", "\r":
                throw PatchbeamError(.commandUnsupportedSyntax, "Enter a single command on one line.")
            case "'", "\"":
                quote = ch
                inToken = true
            case "\\":
                guard let next = iterator.next() else { throw unsupported(ch) }
                current.append(next)
                inToken = true
            case "~" where !inToken:
                throw unsupported(ch)
            default:
                if forbidden.contains(ch) { throw unsupported(ch) }
                current.append(ch)
                inToken = true
            }
        }
        if quote != nil {
            throw PatchbeamError(.commandUnsupportedSyntax, "The command has an unclosed quote.")
        }
        if inToken { args.append(current) }
        guard !args.isEmpty else {
            throw PatchbeamError(.commandRequired, "The chosen check requires a command.", recovery: "For example: python3 -m unittest -v")
        }
        // Leading VAR=value assignments are a shell feature too.
        if let first = args.first, first.contains("="), !first.hasPrefix("-"), !first.contains("/") {
            throw PatchbeamError(.commandUnsupportedSyntax, "Environment assignments (\(first)) aren't supported in checks.")
        }
        return args
    }

    static func unsupported(_ ch: Character) -> PatchbeamError {
        PatchbeamError(.commandUnsupportedSyntax,
                       "Shell features like “\(ch)” aren't supported. Enter one program and its arguments.",
                       recovery: "Patchbeam runs checks without a shell. Wrap complex steps in a script and run that.")
    }

    /// Display form that round-trips through `parse`.
    public static func display(_ argv: [String]) -> String {
        argv.map { arg in
            if arg.isEmpty { return "''" }
            let safe = arg.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:,+@%".contains($0) }
            return safe ? arg : "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }

    /// Reviewable suggestions shown to the user (never auto-run), PRD §13.
    public static func suggestions(forRepositoryAt root: URL) -> [String] {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(name).path) }
        var out: [String] = []
        if has("Package.swift") { out.append("swift test") }
        if has("pyproject.toml") || has("pytest.ini") || has("setup.cfg") { out.append("pytest -q") }
        if (try? fm.contentsOfDirectory(atPath: root.path))?.contains(where: { $0.hasPrefix("test_") && $0.hasSuffix(".py") }) == true {
            out.append("python3 -m unittest -v")
        }
        if has("package.json") { out.append(has("pnpm-lock.yaml") ? "pnpm test" : "npm test") }
        if has("go.mod") { out.append("go test ./...") }
        if has("Cargo.toml") { out.append("cargo test") }
        return out
    }
}
