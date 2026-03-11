// DotNetTestSettingsView.swift — ChorographDotNetTestPlugin
// Settings panel: project directory, dotnet binary path, and health check.

import SwiftUI
import ChorographPluginSDK

struct DotNetTestSettingsView: View {
    @AppStorage("dotnetTestProjectDir") private var projectDir = FileManager.default.currentDirectoryPath
    @AppStorage("dotnetBinaryPath") private var dotnetPath = DotNetTestRunner.defaultDotNetPath

    @State private var healthStatus: HealthStatus = .unknown
    @State private var isChecking = false

    private let runner = DotNetTestRunner()

    var body: some View {
        Form {
            Section("Project") {
                TextField("Project directory", text: $projectDir)
                    .help("Path to the .sln, .csproj, or directory containing tests.")

                HStack {
                    Button("Choose…") { chooseDirectory() }
                    Text(projectDir)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section("dotnet CLI") {
                TextField("Path to dotnet binary", text: $dotnetPath)

                HStack {
                    Button("Check") { Task { await checkHealth() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isChecking)

                    if isChecking { ProgressView().scaleEffect(0.7) }

                    Text(healthStatus.label)
                        .font(.caption)
                        .foregroundStyle(healthStatus.color)
                }
            }

            Section("Info") {
                Text("Install .NET SDK from https://dot.net")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Runs: dotnet test --logger \"console;verbosity=detailed\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task { await checkHealth() }
    }

    private func checkHealth() async {
        isChecking = true
        healthStatus = .checking
        let version = await runner.dotnetVersion(binaryPath: dotnetPath)
        if let v = version {
            healthStatus = .ok(v)
        } else {
            healthStatus = .failed("Not found at '\(dotnetPath)'")
        }
        isChecking = false
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Project Directory"
        if panel.runModal() == .OK, let url = panel.url {
            projectDir = url.path
        }
    }
}

// MARK: - HealthStatus

private enum HealthStatus {
    case unknown, checking, ok(String), failed(String)

    var label: String {
        switch self {
        case .unknown:         return "Not checked"
        case .checking:        return "Checking…"
        case .ok(let v):       return "Found — dotnet \(v)"
        case .failed(let msg): return msg
        }
    }

    var color: Color {
        switch self {
        case .unknown, .checking: return .secondary
        case .ok:                 return .green
        case .failed:             return .red
        }
    }
}
