import Foundation

/// Finds the bundled `broken-python` fixture and turns it into a fresh Git repository.
public enum FixtureLibrary {
    public static let brokenPythonName = "broken-python"
    public static let checkCommand = ["python3", "-m", "unittest", "-v"]
    public static let sampleTraceback = """
    $ python3 -m unittest -v
    test_subtotal (test_calculator.CalculatorTests.test_subtotal) ... ok
    test_total_adds_tax (test_calculator.CalculatorTests.test_total_adds_tax) ... FAIL
    test_total_without_tax (test_calculator.CalculatorTests.test_total_without_tax) ... ok

    ======================================================================
    FAIL: test_total_adds_tax (test_calculator.CalculatorTests.test_total_adds_tax)
    ----------------------------------------------------------------------
    Traceback (most recent call last):
      File "test_calculator.py", line 11, in test_total_adds_tax
        self.assertEqual(total([10.0, 20.0], tax_rate=0.1), 33.0)
    AssertionError: 27.0 != 33.0

    ----------------------------------------------------------------------
    Ran 3 tests in 0.000s

    FAILED (failures=1)
    """

    /// Search order: `PATCHBEAM_FIXTURES`, the app bundle's Resources/Fixtures, then the
    /// source checkout (walking up from this file) for development and tests.
    public static func fixtureDirectory(
        named name: String = brokenPythonName,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sourceFile: String = #filePath
    ) -> URL? {
        var candidates: [URL] = []
        if let env = environment["PATCHBEAM_FIXTURES"] {
            candidates.append(URL(fileURLWithPath: env).appendingPathComponent(name))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Fixtures").appendingPathComponent(name))
        }
        var dir = URL(fileURLWithPath: sourceFile).deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(dir.appendingPathComponent("Tests/Fixtures").appendingPathComponent(name))
            dir.deleteLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("calculator.py").path) }
    }

    /// Copy the fixture into `parent/<repoName>`, `git init`, and commit the broken baseline.
    /// Uses repository-local identity so the user's Git config is never changed.
    public static func makeBrokenPythonRepo(in parent: URL, repoName: String = "broken-python-demo", git: GitClient) async throws -> URL {
        guard let source = fixtureDirectory() else {
            throw PatchbeamError(.notFound, "The bundled broken-python fixture is missing.", recovery: "Rebuild Patchbeam with scripts/build.sh.")
        }
        let target = parent.appendingPathComponent(repoName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw PatchbeamError(.worktreeFailed, "\(target.path) already exists; Patchbeam won't overwrite it.")
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for file in ["calculator.py", "test_calculator.py", "README.md"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(file), to: target.appendingPathComponent(file))
        }
        try FileManager.default.copyItem(at: source.appendingPathComponent("gitignore.fixture"), to: target.appendingPathComponent(".gitignore"))
        try await git.checked(["init", "-q", "-b", "main"], in: target)
        try await git.checked(["config", "user.name", "Patchbeam Fixture"], in: target)
        try await git.checked(["config", "user.email", "fixture@patchbeam.invalid"], in: target)
        try await git.checked(["add", "-A"], in: target)
        try await git.checked(["commit", "-q", "-m", "Seed broken-python fixture (total subtracts tax)"], in: target)
        return PathSafety.canonical(target)
    }
}
