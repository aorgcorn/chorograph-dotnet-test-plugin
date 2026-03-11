// DotNetTestOutputParser.swift — ChorographDotNetTestPlugin
// Parses `dotnet test --logger "console;verbosity=detailed"` stdout lines
// into structured TestResult values.
//
// Example lines handled:
//   "  Passed  MyNamespace.MyTests.SomeTest [12 ms]"
//   "  Failed  MyNamespace.MyTests.BrokenTest [3 ms]"
//   "  Skipped MyNamespace.MyTests.IgnoredTest"
// Error message lines following a failure:
//   "    Error Message:"
//   "     Assert.Equal() Failure. ..."

import Foundation

// MARK: - TestResult

struct TestResult {
    let fullName: String   // e.g. "MyNamespace.MyTests.SomeTest"
    let passed: Bool
    var message: String?   // failure message, if any
}

// MARK: - DotNetTestOutputParser

final class DotNetTestOutputParser {

    // Matches "  Passed  Foo.Bar.TestMethod [12 ms]" or without the timing
    private static let passedRegex = try! NSRegularExpression(
        pattern: #"^\s+Passed\s+(\S+)"#, options: []
    )
    private static let failedRegex = try! NSRegularExpression(
        pattern: #"^\s+Failed\s+(\S+)"#, options: []
    )

    private var pendingFailure: TestResult?
    private var collectingMessage = false
    private var messageLines: [String] = []

    /// Feed one stdout line. Returns a completed `TestResult` when one is ready,
    /// or `nil` if the line is part of an ongoing failure message or unrelated.
    func feed(line: String) -> TestResult? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        // Flush a pending failure once we hit the next test line or a blank line
        // that isn't a message continuation.
        if pendingFailure != nil {
            // Check if we're still collecting the error message block
            if collectingMessage {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("Stack Trace:") || trimmed.hasPrefix("at ") {
                    // Stop collecting on blank line or stack trace
                    collectingMessage = false
                    var result = pendingFailure!
                    result.message = messageLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    pendingFailure = nil
                    messageLines = []
                    return result
                } else if trimmed.hasPrefix("Error Message:") {
                    // Ignore the "Error Message:" header line
                    return nil
                } else {
                    messageLines.append(trimmed)
                    return nil
                }
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("Error Message:") {
                collectingMessage = true
                return nil
            }

            // Non-message line — flush the pending failure without a message
            let result = pendingFailure!
            pendingFailure = nil
            messageLines = []
        }

        if let match = Self.passedRegex.firstMatch(in: line, options: [], range: range) {
            let nameRange = Range(match.range(at: 1), in: line)!
            let name = String(line[nameRange])
            return TestResult(fullName: name, passed: true)
        }

        if let match = Self.failedRegex.firstMatch(in: line, options: [], range: range) {
            let nameRange = Range(match.range(at: 1), in: line)!
            let name = String(line[nameRange])
            pendingFailure = TestResult(fullName: name, passed: false)
            return nil
        }

        return nil
    }

    /// Call after all lines have been fed to flush any trailing pending failure.
    func flush() -> TestResult? {
        guard var result = pendingFailure else { return nil }
        if !messageLines.isEmpty {
            result.message = messageLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        pendingFailure = nil
        messageLines = []
        return result
    }

    // MARK: - Path resolution

    /// Convert a dotted test class name to a probable relative file path.
    /// e.g. "MyApp.Tests.UnitTests.AuthTests.ShouldLogin" → "MyApp/Tests/UnitTests/AuthTests.cs"
    static func resolveFilePath(for fullName: String, projectDirectory: String) -> String {
        // Split on dots; the last component is the method name, second-to-last is the class.
        var components = fullName.split(separator: ".").map(String.init)
        guard components.count >= 2 else {
            return (projectDirectory as NSString).appendingPathComponent("\(fullName).cs")
        }
        _ = components.removeLast() // remove method name
        let className = components.last!  // class name is now last
        // Build a relative path from namespace components → directories + class file
        let relPath = components.joined(separator: "/") + ".cs"
        return (projectDirectory as NSString).appendingPathComponent(relPath)
    }
}
