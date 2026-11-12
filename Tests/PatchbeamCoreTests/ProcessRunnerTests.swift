import Foundation
import Testing
@testable import PatchbeamCore

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    let runner = ProcessRunner()
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())

    func spec(_ exe: String, _ args: [String], timeout: Duration? = nil, limit: Int = 1 << 20, stdin: Data? = nil) -> ProcessSpec {
        ProcessSpec(executable: URL(fileURLWithPath: exe), arguments: args, workingDirectory: tmp,
                    environment: MinimalEnvironment.make(), stdin: stdin, timeout: timeout, outputLimitBytes: limit)
    }

    @Test func capturesExitCodeAndStreams() async throws {
        let r = try await runner.run(spec("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"]))
        #expect(r.exitCode == 3)
        #expect(r.stdoutString == "out\n")
        #expect(r.stderrString == "err\n")
        #expect(!r.succeeded)
    }

    @Test func argumentsAreNotShellInterpreted() async throws {
        // A hostile-looking argument must arrive verbatim, never expanded.
        let hostile = "$(touch /tmp/patchbeam-pwned); `id`; | rm -rf ~"
        let r = try await runner.run(spec("/bin/echo", [hostile]))
        #expect(r.stdoutString == hostile + "\n")
        #expect(!FileManager.default.fileExists(atPath: "/tmp/patchbeam-pwned"))
    }

    @Test func timeoutKillsProcessGroup() async throws {
        let start = Date()
        // The child sleeps; the grandchild would outlive a naive kill(pid).
        let r = try await runner.run(spec("/bin/sh", ["-c", "sleep 30 & sleep 30"], timeout: .milliseconds(300)))
        #expect(r.timedOut)
        #expect(r.signal == SIGTERM)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func cancelReportsCancelledNotTimeout() async throws {
        let p = try runner.start(spec("/bin/sleep", ["30"]))
        p.cancel(grace: 0.5)
        let r = await p.waitForExit()
        #expect(r.cancelled)
        #expect(!r.timedOut)
        #expect(r.signal != nil)
    }

    @Test func outputIsCapped() async throws {
        let r = try await runner.run(spec("/bin/sh", ["-c", "yes patchbeam | head -c 500000"], limit: 1000))
        #expect(r.stdout.count == 1000)
        #expect(r.stdoutTruncated)
        #expect(r.exitCode == 0)
    }

    @Test func stdinIsDelivered() async throws {
        let r = try await runner.run(spec("/bin/cat", [], stdin: Data("hello\nworld".utf8)))
        #expect(r.stdoutString == "hello\nworld")
    }

    @Test func environmentIsMinimal() async throws {
        let r = try await runner.run(spec("/usr/bin/env", []))
        let keys = Set(r.stdoutString.split(separator: "\n").compactMap { $0.split(separator: "=").first.map(String.init) })
        #expect(keys.isSubset(of: ["HOME", "PATH", "LANG", "LC_ALL", "TERM", "NO_COLOR", "USER", "LOGNAME", "TMPDIR", "SHELL"]))
    }

    @Test func missingExecutableThrowsTypedError() {
        #expect(throws: ProcessLaunchError.self) {
            _ = try runner.start(spec("/nonexistent/tool", []))
        }
    }

    @Test func streamingYieldsChunks() async throws {
        var s = spec("/bin/sh", ["-c", "echo a; echo b"])
        s.streamOutput = true
        let p = try runner.start(s)
        var collected = Data()
        for await chunk in p.output where chunk.stream == .stdout { collected.append(chunk.data) }
        _ = await p.waitForExit()
        #expect(String(decoding: collected, as: UTF8.self) == "a\nb\n")
    }
}
