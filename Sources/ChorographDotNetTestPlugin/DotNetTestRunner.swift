// DotNetTestRunner.swift — ChorographDotNetTestPlugin
// Actor that runs `dotnet test` as a subprocess and streams structured results.

import Foundation
import ChorographPluginSDK

// MARK: - DotNetTestRunner

actor DotNetTestRunner {

    static let defaultDotNetPath: String = {
        let candidates = [
            "/usr/local/share/dotnet/dotnet",
            "/opt/homebrew/bin/dotnet",
            "/usr/local/bin/dotnet",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        // Fall back to asking the shell — covers custom installs and nix-style envs.
        if let found = runWhich("dotnet") { return found }
        return candidates[0]
    }()

    private static func runWhich(_ tool: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [tool]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }

    private var activeProcess: Process?

    // MARK: - Health

    func dotnetVersion(binaryPath: String) async -> String? {
        await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binaryPath)
            p.arguments = ["--version"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let v = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: v?.isEmpty == false ? v : nil)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Run

    /// Run `dotnet test` in `projectDirectory` and stream results.
    /// Calls `onResult` on each parsed test result (from any thread).
    /// Calls `onLine` for every raw stdout line (for activity log).
    /// Returns the process exit code.
    func run(
        dotnetPath: String,
        projectDirectory: String,
        onResult: @escaping @Sendable (TestResult) -> Void,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: dotnetPath)
        process.arguments = [
            "test",
            "--logger", "console;verbosity=detailed",
            "--no-logo",
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: projectDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe
        process.standardInput  = FileHandle.nullDevice

        activeProcess = process

        // Box the continuation so it can be safely captured by @Sendable closures.
        final class ContinuationBox: @unchecked Sendable {
            var value: AsyncStream<Data>.Continuation?
        }
        let box = ContinuationBox()
        let stdoutStream = AsyncStream<Data> { box.value = $0 }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                box.value?.finish()
            } else {
                box.value?.yield(data)
            }
        }
        process.terminationHandler = { _ in box.value?.finish() }

        do {
            try process.run()
        } catch {
            activeProcess = nil
            return -1
        }

        let parser = DotNetTestOutputParser()
        var lineBuffer = ""

        for await chunk in stdoutStream {
            guard let text = String(data: chunk, encoding: .utf8) else { continue }
            lineBuffer += text
            while let nl = lineBuffer.range(of: "\n") {
                let line = String(lineBuffer[lineBuffer.startIndex..<nl.lowerBound])
                lineBuffer = String(lineBuffer[nl.upperBound...])
                onLine(line)
                if let result = parser.feed(line: line) {
                    onResult(result)
                }
            }
        }
        // Flush remaining
        if !lineBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
            onLine(lineBuffer)
            if let result = parser.feed(line: lineBuffer) { onResult(result) }
        }
        if let result = parser.flush() { onResult(result) }

        process.waitUntilExit()
        activeProcess = nil
        return process.terminationStatus
    }

    func abort() {
        activeProcess?.terminate()
        activeProcess = nil
    }
}
