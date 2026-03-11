// RunTestsCommand.swift — ChorographDotNetTestPlugin
// PluginCommand that runs `dotnet test` and emits PluginEvents so the host
// pulses spatial map nodes green (pass) or red (fail) for each test.

import Foundation
import ChorographPluginSDK

// MARK: - RunTestsCommand

struct RunTestsCommand: PluginCommand {
    let id = "com.chorograph.plugin.dotnet-test.runTests"
    let title = "Run .NET Tests"
    let keyboardShortcutHint: String? = "⌃⌥T"

    private let runner: DotNetTestRunner

    init(runner: DotNetTestRunner) {
        self.runner = runner
    }

    @MainActor
    func execute(context: any PluginContextProviding) async throws {
        let projectDir = UserDefaults.standard.string(forKey: "dotnetTestProjectDir")
            ?? FileManager.default.currentDirectoryPath
        let dotnetPath = UserDefaults.standard.string(forKey: "dotnetBinaryPath")
            ?? DotNetTestRunner.defaultDotNetPath

        guard FileManager.default.isExecutableFile(atPath: dotnetPath) else {
            throw DotNetTestError.binaryNotFound(dotnetPath)
        }

        // Capture context for use inside the detached task.
        let ctx = context

        // Fire-and-forget: results stream in asynchronously via context.emitEvent.
        Task.detached(priority: .userInitiated) {
            let exitCode = await runner.run(
                dotnetPath: dotnetPath,
                projectDirectory: projectDir,
                onResult: { result in
                    let filePath = DotNetTestOutputParser.resolveFilePath(
                        for: result.fullName,
                        projectDirectory: projectDir
                    )
                    // Warm the node before the pass/fail pulse lands.
                    Task { @MainActor in
                        ctx.emitEvent(RuntimeHeatEvent(path: filePath, intensity: 0.6))
                        ctx.emitEvent(RuntimeTestResultEvent(
                            path: filePath,
                            passed: result.passed,
                            message: result.message
                        ))
                    }
                },
                onLine: { _ in }
            )

            if exitCode != 0 && exitCode != 1 {
                // Exit code 1 = tests ran but some failed (normal). Anything else is an error.
                Task { @MainActor in
                    ctx.emitEvent(ErrorEvent("dotnet test exited with code \(exitCode)"))
                }
            }
        }
    }
}

// MARK: - DotNetTestError

enum DotNetTestError: LocalizedError {
    case binaryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "dotnet binary not found at '\(path)'. Check the path in dotnet test Settings."
        }
    }
}
