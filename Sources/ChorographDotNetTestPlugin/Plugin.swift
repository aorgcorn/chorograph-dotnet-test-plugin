// Plugin.swift — ChorographDotNetTestPlugin
// Entry point: registers a "Run .NET Tests" command and settings panel.

import ChorographPluginSDK
import SwiftUI

public final class DotNetTestPlugin: ChorographPlugin, @unchecked Sendable {

    public let manifest = PluginManifest(
        id: "com.chorograph.plugin.dotnet-test",
        displayName: "dotnet test",
        description: "Runs dotnet test and pulses test file nodes on the spatial map with pass/fail results.",
        version: "1.0.1",
        capabilities: [.commandBarEntry, .settingsPanel, .customEvents]
    )

    public init() {}

    public func bootstrap(context: any PluginContextProviding) async throws {
        let runner = DotNetTestRunner()
        context.registerCommand(RunTestsCommand(runner: runner))
        context.registerSettingsPanel(title: "dotnet test", AnyView(DotNetTestSettingsView()))
    }
}

// MARK: - C-ABI factory (required for dlopen-based loading)

@_cdecl("chorograph_plugin_create")
public func chorographPluginCreate() -> UnsafeMutableRawPointer {
    let plugin = DotNetTestPlugin()
    return Unmanaged.passRetained(plugin as AnyObject).toOpaque()
}
