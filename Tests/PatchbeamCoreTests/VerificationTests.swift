import Foundation
import Testing
@testable import PatchbeamCore

@Suite("Command parsing")
struct CommandParserTests {
    @Test func parsesQuotedArguments() throws {
        #expect(try CommandLineParser.parse("python3 -m unittest -v") == ["python3", "-m", "unittest", "-v"])
        #expect(try CommandLineParser.parse(#"npm test -- --testNamePattern "adds tax""#) == ["npm", "test", "--", "--testNamePattern", "adds tax"])
        #expect(try CommandLineParser.parse("pytest 'tests/my file.py'") == ["pytest", "tests/my file.py"])
        #expect(try CommandLineParser.parse(#"echo a\ b"#) == ["echo", "a b"])
        #expect(try CommandLineParser.parse("go test ./...") == ["go", "test", "./..."])
    }

    @Test(arguments: ["npm test | tee x", "make && rm -rf /", "pytest; curl evil", "echo $HOME", "echo `id`",
                      "cat < /etc/passwd", "pytest tests/*", "FOO=1 pytest", "ls ~", "a\nb", #"echo "$(id)""#])
    func rejectsShellFeatures(_ input: String) {
        #expect(throws: PatchbeamError.self) { try CommandLineParser.parse(input) }
    }

    @Test func rejectsEmptyAndUnclosed() {
        #expect(throws: PatchbeamError.self) { try CommandLineParser.parse("   ") }
        #expect(throws: PatchbeamError.self) { try CommandLineParser.parse("echo 'oops") }
    }

    @Test func displayRoundTrips() throws {
        let argv = ["pytest", "tests/my file.py", "-k", "it's", ""]
        #expect(try CommandLineParser.parse(CommandLineParser.display(argv)) == argv)
    }
}

@Suite("Test output parsing")
struct TestOutputParserTests {
    @Test func unittestFailure() {
        let s = "F.\n======\nFAIL: test_total\n----\nRan 2 tests in 0.001s\n\nFAILED (failures=1)\n"
        let p = TestOutputParser.parse(s)
        #expect(p?.framework == "unittest" && p?.total == 2 && p?.failed == 1 && p?.passed == 1)
    }

    @Test func unittestNoTests() {
        let p = TestOutputParser.parse("\n----\nRan 0 tests in 0.000s\n\nNO TESTS RAN\n")
        #expect(p?.noTestsRan == true)
    }

    @Test func pytestSummary() {
        let p = TestOutputParser.parse("===== 24 passed, 1 failed, 2 skipped in 0.52s =====")
        #expect(p?.framework == "pytest" && p?.passed == 24 && p?.failed == 1 && p?.skipped == 2)
        #expect(TestOutputParser.parse("====== no tests ran in 0.01s ======")?.noTestsRan == true)
    }

    @Test func jestCargoXCTest() {
        #expect(TestOutputParser.parse("Tests:       1 failed, 24 passed, 25 total")?.failed == 1)
        #expect(TestOutputParser.parse("test result: ok. 7 passed; 0 failed; 1 ignored; 0 measured")?.passed == 7)
        #expect(TestOutputParser.parse("Executed 12 tests, with 0 failures (0 unexpected)")?.total == 12)
    }

    @Test func unknownOutputYieldsNoCounts() {
        #expect(TestOutputParser.parse("build ok\nall good") == nil)
    }
}

@Suite("VerificationRunner", .serialized)
struct VerificationRunnerTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pb-verify-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func recipe(_ cmd: String, timeout: Int = 30) throws -> VerificationRecipe {
        VerificationRecipe(argv: try CommandLineParser.parse(cmd), display: cmd, timeoutSeconds: timeout).approving()
    }

    func run(_ r: VerificationRecipe) async -> VerificationRecord {
        await VerificationRunner().run(recipe: r, capsuleID: UUID(), kind: .patch, worktree: dir,
                                       logDirectory: dir.appendingPathComponent("logs"), patchFingerprint: "fp")
    }

    @Test func exitZeroPasses() async throws {
        try Data("import unittest\nclass T(unittest.TestCase):\n  def test_a(self): self.assertTrue(True)\n".utf8)
            .write(to: dir.appendingPathComponent("test_ok.py"))
        let rec = await run(try recipe("python3 -m unittest -v"))
        #expect(rec.result == .passed)
        #expect(rec.exitCode == 0)
        #expect(rec.parsed?.total == 1)
        #expect(rec.executablePath?.hasSuffix("python3") == true)
        #expect(try String(contentsOfFile: rec.stderrLogPath!, encoding: .utf8).contains("Ran 1 test"))
    }

    @Test func exitOneFailsWithCode() async throws {
        let rec = await run(try recipe("/bin/sh -c 'exit 1'".replacingOccurrences(of: "'", with: "\"")))
        #expect(rec.result == .failed)
        #expect(rec.exitCode == 1)
        #expect(rec.headline == "Check failed (exit 1)")
    }

    @Test func exitZeroButNoTestsIsInconclusive() async throws {
        let empty = dir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let rec = await VerificationRunner().run(recipe: try recipe("python3 -m unittest"), capsuleID: UUID(), kind: .patch,
                                                 worktree: empty, logDirectory: dir, patchFingerprint: nil)
        // Python ≥3.12 exits 5 for "NO TESTS RAN"; older versions exit 0. Neither may pass.
        #expect(rec.result != .passed)
    }

    @Test func timeoutIsRecorded() async throws {
        let rec = await run(try recipe("/bin/sleep 20", timeout: 1))
        #expect(rec.result == .timedOut)
        #expect(rec.signal != nil)
    }

    @Test func unapprovedRecipeNeverRuns() async throws {
        let marker = dir.appendingPathComponent("ran")
        let r = VerificationRecipe(argv: ["/usr/bin/touch", marker.path], display: "touch")
        let rec = await run(r)
        #expect(rec.result == .launchFailed)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func missingProgramIsActionable() async throws {
        let rec = await run(try recipe("definitely-not-a-tool-pb"))
        #expect(rec.result == .launchFailed)
        #expect(rec.outputTail.contains("Couldn't find"))
    }

    @Test func relativeExecutableCannotEscapeWorktree() async throws {
        let rec = await run(try recipe("../../../../../bin/sh"))
        #expect(rec.result == .launchFailed)
        #expect(rec.outputTail.contains("outside the repair worktree"))
    }

    @Test func signalIsRecorded() async throws {
        let rec = await run(try recipe(#"python3 -c "import os, signal; os.kill(os.getpid(), signal.SIGKILL)""#))
        #expect(rec.result == .failed)
        #expect(rec.signal == 9)
        #expect(rec.exitCode == nil)
        #expect(rec.headline == "Check killed by signal 9")
    }
}
