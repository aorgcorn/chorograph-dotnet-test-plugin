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

        // Capture context for use inside the detached task.
        let ctx = context

        // Fire-and-forget: results stream in asynchronously via context.emitEvent.
        Task.detached(priority: .userInitiated) {
            // Verify binary before spawning.
            guard FileManager.default.isExecutableFile(atPath: dotnetPath) else {
                Task { @MainActor in
                    ctx.emitEvent(ErrorEvent(
                        "dotnet not found at '\(dotnetPath)'. Set the correct path in Settings (⌘,)."
                    ))
                }
                return
            }

            Task { @MainActor in
                ctx.emitEvent(InfoEvent("Running dotnet test in \(projectDir)…"))
            }

            let exitCode = await runner.run(
                dotnetPath: dotnetPath,
                projectDirectory: projectDir,
                onResult: { result in
                    let filePath = DotNetTestOutputParser.resolveFilePath(
                        for: result.fullName,
                        projectDirectory: projectDir
                    )
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

            Task { @MainActor in
                if exitCode == 0 {
                    ctx.emitEvent(InfoEvent("dotnet test finished — all tests passed."))
                } else if exitCode == 1 {
                    ctx.emitEvent(InfoEvent("dotnet test finished — some tests failed."))
                } else {
                    ctx.emitEvent(ErrorEvent("dotnet test exited with code \(exitCode)."))
                }
            }
        }
    }
}
