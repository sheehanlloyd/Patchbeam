import Darwin
import Foundation

/// A fully specified child process. There is deliberately no "shell string" form:
/// callers always pass an executable URL plus an argv array (PRD §12.3).
public struct ProcessSpec: Sendable {
    public var executable: URL
    public var arguments: [String]
    public var workingDirectory: URL
    public var environment: [String: String]
    public var stdin: Data?
    public var timeout: Duration?
    /// Maximum bytes retained per stream. Further output is drained and discarded.
    public var outputLimitBytes: Int
    /// When true, chunks are also yielded on `RunningProcess.output` (agents). Otherwise only buffered.
    public var streamOutput: Bool

    public init(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        stdin: Data? = nil,
        timeout: Duration? = nil,
        outputLimitBytes: Int = 2 * 1024 * 1024,
        streamOutput: Bool = false
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.stdin = stdin
        self.timeout = timeout
        self.outputLimitBytes = outputLimitBytes
        self.streamOutput = streamOutput
    }
}

public enum ProcessTermination: Sendable, Equatable {
    case exited(Int32)
    case signaled(Int32)
}

public struct ProcessResult: Sendable {
    public var termination: ProcessTermination
    public var stdout: Data
    public var stderr: Data
    public var stdoutTruncated: Bool
    public var stderrTruncated: Bool
    public var duration: TimeInterval
    public var timedOut: Bool
    public var cancelled: Bool

    public var exitCode: Int32? {
        if case .exited(let code) = termination { return code }
        return nil
    }

    public var signal: Int32? {
        if case .signaled(let sig) = termination { return sig }
        return nil
    }

    public var succeeded: Bool { termination == .exited(0) && !timedOut && !cancelled }
    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

public enum ProcessStream: Sendable { case stdout, stderr }

public struct ProcessOutputChunk: Sendable {
    public var stream: ProcessStream
    public var data: Data
}

public enum ProcessLaunchError: Error, Sendable, CustomStringConvertible {
    case executableNotFound(String)
    case workingDirectoryMissing(String)
    case spawnFailed(errno: Int32, executable: String)

    public var description: String {
        switch self {
        case .executableNotFound(let path): "Executable not found or not executable: \(path)"
        case .workingDirectoryMissing(let path): "Working directory does not exist: \(path)"
        case .spawnFailed(let code, let exe): "Could not start \(exe): \(String(cString: strerror(code)))"
        }
    }
}

/// A running child process in its **own process group**, so cancellation can signal
/// the whole tree without matching unrelated processes by name (PRD §12.3).
public final class RunningProcess: @unchecked Sendable {
    public let pid: pid_t
    public let output: AsyncStream<ProcessOutputChunk>

    private let lock = NSLock()
    private var exited = false
    private var cancelRequested = false
    private var timedOutFlag = false
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var stdoutTruncated = false
    private var stderrTruncated = false
    private let limit: Int
    private let streams: Bool
    private let started = Date()
    private let exitSemaphore = DispatchSemaphore(value: 0)
    private var termination: ProcessTermination = .exited(-1)
    private var openStreams = 2
    private let streamsDone = DispatchSemaphore(value: 0)
    private let continuation: AsyncStream<ProcessOutputChunk>.Continuation
    private var waiters: [CheckedContinuation<ProcessResult, Never>] = []
    private var finalResult: ProcessResult?

    fileprivate init(pid: pid_t, limit: Int, stdoutFD: Int32, stderrFD: Int32, stdinFD: Int32, stdin: Data?, timeout: Duration?, streams: Bool) {
        self.pid = pid
        self.limit = limit
        self.streams = streams
        var cont: AsyncStream<ProcessOutputChunk>.Continuation!
        self.output = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont

        startReader(fd: stdoutFD, stream: .stdout)
        startReader(fd: stderrFD, stream: .stderr)
        startStdinWriter(fd: stdinFD, data: stdin)
        startWaiter()
        if let timeout {
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let alreadyExited = self.exited
                if !alreadyExited { self.timedOutFlag = true }
                self.lock.unlock()
                if !alreadyExited { self.terminateGroup() }
            }
        }
    }

    private func startStdinWriter(fd: Int32, data: Data?) {
        Thread.detachNewThread {
            if let data, !data.isEmpty {
                data.withUnsafeBytes { raw in
                    guard var ptr = raw.baseAddress else { return }
                    var remaining = raw.count
                    while remaining > 0 {
                        let n = Darwin.write(fd, ptr, remaining)
                        if n <= 0 { break }
                        remaining -= n
                        ptr = ptr.advanced(by: n)
                    }
                }
            }
            close(fd)
        }
    }

    private func startReader(fd: Int32, stream: ProcessStream) {
        Thread.detachNewThread { [self] in
            let size = 64 * 1024
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
            defer { buffer.deallocate() }
            while true {
                let n = read(fd, buffer, size)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                let chunk = Data(bytes: buffer, count: n)
                append(chunk, to: stream)
                if streams { continuation.yield(ProcessOutputChunk(stream: stream, data: chunk)) }
            }
            close(fd)
            lock.lock()
            openStreams -= 1
            let done = openStreams == 0
            lock.unlock()
            if done { streamsDone.signal() }
        }
    }

    private func append(_ chunk: Data, to stream: ProcessStream) {
        lock.lock()
        defer { lock.unlock() }
        switch stream {
        case .stdout:
            let room = max(0, limit - stdoutBuffer.count)
            if room > 0 { stdoutBuffer.append(chunk.prefix(room)) }
            if chunk.count > room { stdoutTruncated = true }
        case .stderr:
            let room = max(0, limit - stderrBuffer.count)
            if room > 0 { stderrBuffer.append(chunk.prefix(room)) }
            if chunk.count > room { stderrTruncated = true }
        }
    }

    private func startWaiter() {
        Thread.detachNewThread { [self] in
            var status: Int32 = 0
            var r: pid_t
            repeat { r = waitpid(pid, &status, 0) } while r == -1 && errno == EINTR
            let term: ProcessTermination
            if (status & 0x7f) == 0 {
                term = .exited((status >> 8) & 0xff)
            } else {
                term = .signaled(status & 0x7f)
            }
            lock.lock()
            exited = true
            termination = term
            lock.unlock()
            // Children of the group may still hold the pipes; give readers a bounded window.
            if streamsDone.wait(timeout: .now() + 5) == .timedOut {
                killpg(pid, SIGKILL)
                _ = streamsDone.wait(timeout: .now() + 2)
            }
            continuation.finish()
            lock.lock()
            let result = ProcessResult(
                termination: term,
                stdout: stdoutBuffer,
                stderr: stderrBuffer,
                stdoutTruncated: stdoutTruncated,
                stderrTruncated: stderrTruncated,
                duration: Date().timeIntervalSince(started),
                timedOut: timedOutFlag,
                cancelled: cancelRequested && !timedOutFlag
            )
            finalResult = result
            let pending = waiters
            waiters = []
            lock.unlock()
            for w in pending { w.resume(returning: result) }
        }
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return !exited
    }

    /// Wait for exit and collected output.
    public func waitForExit() async -> ProcessResult {
        await withCheckedContinuation { (c: CheckedContinuation<ProcessResult, Never>) in
            lock.lock()
            if let finalResult {
                lock.unlock()
                c.resume(returning: finalResult)
            } else {
                waiters.append(c)
                lock.unlock()
            }
        }
    }

    /// SIGTERM the process group, then SIGKILL after a grace period. Only signals our own group.
    public func cancel(grace: TimeInterval = 2) {
        lock.lock()
        let alreadyExited = exited
        if !alreadyExited { cancelRequested = true }
        lock.unlock()
        guard !alreadyExited else { return }
        terminateGroup(grace: grace)
    }

    private func terminateGroup(grace: TimeInterval = 2) {
        killpg(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
            guard let self, self.isRunning else { return }
            killpg(self.pid, SIGKILL)
        }
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    /// Spawn with posix_spawn: new process group, closed inherited descriptors, default signals.
    public func start(_ spec: ProcessSpec) throws -> RunningProcess {
        let exePath = spec.executable.path
        guard FileManager.default.isExecutableFile(atPath: exePath) else {
            throw ProcessLaunchError.executableNotFound(exePath)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: spec.workingDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProcessLaunchError.workingDirectoryMissing(spec.workingDirectory.path)
        }

        var inPipe: [Int32] = [0, 0], outPipe: [Int32] = [0, 0], errPipe: [Int32] = [0, 0]
        guard pipe(&inPipe) == 0, pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            throw ProcessLaunchError.spawnFailed(errno: errno, executable: exePath)
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, inPipe[0], 0)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], 2)
        posix_spawn_file_actions_addchdir_np(&fileActions, spec.workingDirectory.path)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attr, Int16(flags))
        posix_spawnattr_setpgroup(&attr, 0)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attr, &allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attr, &noSignals)

        let argv: [UnsafeMutablePointer<CChar>?] = ([exePath] + spec.arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = spec.environment
            .sorted { $0.key < $1.key }
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exePath, &fileActions, &attr, argv, envp)
        close(inPipe[0]); close(outPipe[1]); close(errPipe[1])
        guard rc == 0 else {
            close(inPipe[1]); close(outPipe[0]); close(errPipe[0])
            throw ProcessLaunchError.spawnFailed(errno: rc, executable: exePath)
        }
        return RunningProcess(
            pid: pid,
            limit: spec.outputLimitBytes,
            stdoutFD: outPipe[0],
            stderrFD: errPipe[0],
            stdinFD: inPipe[1],
            stdin: spec.stdin,
            timeout: spec.timeout,
            streams: spec.streamOutput
        )
    }

    /// Convenience: run to completion.
    public func run(_ spec: ProcessSpec) async throws -> ProcessResult {
        let process = try start(spec)
        return await withTaskCancellationHandler {
            await process.waitForExit()
        } onCancel: {
            process.cancel()
        }
    }
}
