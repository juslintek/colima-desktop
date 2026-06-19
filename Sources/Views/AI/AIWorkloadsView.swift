import SwiftUI

struct AIWorkloadsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedModel = "gemma3"
    @State private var runner = "docker"
    @State private var selectedTab = 0
    @State private var pullingModel: String?
    @State private var errorMessage: String?

    private let tabNames = ["Downloaded", "Docker AI", "HuggingFace", "Ollama"]

    private var vmType: String { appState.vmType.isEmpty ? "unknown" : appState.vmType }
    private var krunkitAvailable: Bool { vmType == "krunkit" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                prerequisitesSection
                modelLibrarySection
                activeModelsSection
                legacyQuickActions
                Spacer()
            }
            .padding()
        }
        .navigationTitle("AI Workloads")
        .task { await appState.refreshAIModels(runner: runner) }
    }

    // MARK: - Section 1: Prerequisites

    private var prerequisitesSection: some View {
        GroupBox("Prerequisites & Status") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(krunkitAvailable ? .green : .red).frame(width: 10, height: 10)
                        .accessibilityIdentifier("status_indicator_krunkit")
                    Text(krunkitAvailable ? "Krunkit Available" : "Krunkit Not Found")
                    Spacer()
                    Button("Install Krunkit") { appState.showToast("Krunkit installed") }
                        .accessibilityIdentifier("btn_install_ai_krunkit")
                }
                if !krunkitAvailable {
                    warningRow("VM type is '\(vmType)'. krunkit recommended for AI workloads.") {
                        Button("Switch to krunkit") { appState.showToast("Requires VM recreation with --vm-type krunkit") }.font(.caption)
                    }
                }
                if let err = errorMessage {
                    warningRow(err, color: .red) { EmptyView() }
                }
            }
        }
    }

    private func warningRow<V: View>(_ text: String, color: Color = .orange, @ViewBuilder trailing: () -> V) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color)
            Text(text).font(.caption).accessibilityIdentifier("text_ai_ram_warning")
            Spacer()
            trailing()
        }
    }

    // MARK: - Section 2: Model Library

    private var modelLibrarySection: some View {
        GroupBox("Model Library") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Model name", text: $selectedModel)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                        .accessibilityIdentifier("field_ai_modelname")
                    Picker("Runner", selection: $runner) {
                        Text("docker").tag("docker"); Text("ramalama").tag("ramalama")
                    }.frame(maxWidth: 150).accessibilityIdentifier("field_ai_runner")
                    Button("Run") { runModel(selectedModel) }
                        .accessibilityIdentifier("btn_run_ai_model")
                    Button("Serve") { serveModel(selectedModel) }
                        .accessibilityIdentifier("btn_serve_ai_model")
                }
                Picker("Tab", selection: $selectedTab) {
                    ForEach(0..<tabNames.count, id: \.self) { Text(tabNames[$0]).tag($0) }
                }.pickerStyle(.segmented)

                switch selectedTab {
                case 0: downloadedTab
                case 1: registryTab("dockerai", models: MockK8sData.dockerAIModels)
                case 2: registryTab("huggingface", models: MockK8sData.huggingFaceModels)
                case 3: registryTab("ollama", models: MockK8sData.ollamaModels)
                default: EmptyView()
                }
            }
        }.accessibilityIdentifier("table_ai_models")
    }

    private var downloadedTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.aiModels.isEmpty {
                Text("No models downloaded. Pull a model or use `colima model pull <name>`.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(appState.aiModels) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.name).fontWeight(.medium)
                            Text("\(model.size) • \(model.status)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.status == "idle" {
                            Button("Run") { runModel(model.name) }
                                .font(.caption).accessibilityIdentifier("btn_ai_run_\(model.name)")
                            Button("Serve") { serveModel(model.name) }
                                .font(.caption).accessibilityIdentifier("btn_ai_serve_\(model.name)")
                        }
                        Button("Delete") { deleteModel(model.name) }
                            .foregroundStyle(.red).font(.caption).accessibilityIdentifier("btn_ai_delete_\(model.name)")
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }.accessibilityIdentifier("tab_ai_downloaded")
    }

    private func registryTab(_ id: String, models: [(name: String, desc: String, size: String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(models, id: \.name) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(m.name).fontWeight(.medium)
                            Text(m.desc).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(m.size).font(.caption).foregroundStyle(.secondary)
                        if pullingModel == m.name {
                            Button("Cancel") { pullingModel = nil }
                                .font(.caption)
                        } else {
                            Button("Pull") { pullModel(m.name) }
                                .font(.caption).accessibilityIdentifier("btn_ai_pull_\(m.name)")
                        }
                    }
                    if pullingModel == m.name {
                        PullProgressView(name: m.name) { pullingModel = nil }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }.accessibilityIdentifier("tab_ai_\(id)")
    }

    // MARK: - Section 3: Active Models

    private var activeModelsSection: some View {
        GroupBox("Active Models") {
            let active = appState.aiModels.filter { $0.status != "idle" }
            if active.isEmpty {
                Text("No active models").foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(active) { model in
                    HStack {
                        Circle().fill(model.status == "serving" ? .green : .blue).frame(width: 8, height: 8)
                        Text(model.name).fontWeight(.medium)
                        Text("(\(model.size))").foregroundStyle(.secondary)
                        Spacer()
                        if model.status == "serving", let port = model.port {
                            Text("http://localhost:\(port)")
                                .font(.system(.caption, design: .monospaced))
                                .accessibilityIdentifier("text_ai_serve_url")
                            Button("Open") {
                                NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)
                            }
                            .font(.caption).accessibilityIdentifier("btn_ai_open_browser")
                        }
                        Button("Stop") { stopModel(model.name) }
                            .foregroundStyle(.red).font(.caption).accessibilityIdentifier("btn_ai_stop_\(model.name)")
                    }
                }
            }
        }
    }

    @State private var showSetupFlow = false
    @State private var showModelBrowser = false

    private var legacyQuickActions: some View {
        GroupBox("Quick Actions") {
            HStack(spacing: 8) {
                Button("Setup") { showSetupFlow = true }.accessibilityIdentifier("btn_setup_ai_model")
                Button("Browse Models") { showModelBrowser = true }.accessibilityIdentifier("btn_browse_ai_registry")
                Button("Create AI Profile") {
                    Task {
                        do {
                            try await appState.services.createProfile(name: "ai", config: ColimaStartConfig(vmType: "krunkit", runtime: "docker"))
                            appState.showToast("AI profile created")
                        } catch { errorMessage = error.localizedDescription }
                    }
                }.accessibilityIdentifier("btn_createprofile_ai_new")
            }

            if showSetupFlow {
                AISetupProgressView(runner: runner) { showSetupFlow = false }
            }

            if showModelBrowser {
                ModelBrowserView(runner: runner, onPull: pullModel) { showModelBrowser = false }
            }
        }
    }

    // MARK: - Real actions

    private func pullModel(_ name: String) {
        pullingModel = name
        errorMessage = nil
        Task {
            do {
                try await appState.services.modelPull(name: name, runner: runner)
                await appState.refreshAIModels(runner: runner)
                pullingModel = nil
            } catch {
                errorMessage = "Pull failed: \(error.localizedDescription)"
                pullingModel = nil
            }
        }
    }

    private func runModel(_ name: String) {
        errorMessage = nil
        Task {
            do {
                try await appState.services.modelRun(name: name, runner: runner)
                await appState.refreshAIModels(runner: runner)
            } catch { errorMessage = "Run failed: \(error.localizedDescription)" }
        }
    }

    private func serveModel(_ name: String) {
        errorMessage = nil
        Task {
            do {
                try await appState.services.modelServe(name: name, runner: runner, port: 8080)
                await appState.refreshAIModels(runner: runner)
            } catch { errorMessage = "Serve failed: \(error.localizedDescription)" }
        }
    }

    private func stopModel(_ name: String) {
        Task {
            do {
                try await appState.services.modelStop(name: name)
                await appState.refreshAIModels(runner: runner)
            } catch { errorMessage = "Stop failed: \(error.localizedDescription)" }
        }
    }

    private func deleteModel(_ name: String) {
        Task {
            do {
                // colima model doesn't have a delete — remove via docker rmi
                _ = try await appState.services.executeCommand(tool: "docker", args: ["rmi", name])
                await appState.refreshAIModels(runner: runner)
            } catch { errorMessage = "Delete failed: \(error.localizedDescription)" }
        }
    }
}

// MARK: - Model Browser

struct ModelBrowserView: View {
    let runner: String
    let onPull: (String) -> Void
    let onClose: () -> Void
    @State private var selectedRegistry = "Docker AI"
    @State private var searchText = ""

    private let registries = ["Docker AI", "HuggingFace", "Ollama"]

    private var models: [(name: String, desc: String, size: String)] {
        switch selectedRegistry {
        case "Docker AI": return MockK8sData.dockerAIModels
        case "HuggingFace": return MockK8sData.huggingFaceModels
        default: return MockK8sData.ollamaModels
        }
    }

    private var filteredModels: [(name: String, desc: String, size: String)] {
        guard !searchText.isEmpty else { return models }
        return models.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.desc.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model Browser").font(.caption.weight(.semibold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.borderless)
            }
            Picker("Registry", selection: $selectedRegistry) {
                ForEach(registries, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            TextField("Search models...", text: $searchText).textFieldStyle(.roundedBorder).font(.caption)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filteredModels, id: \.name) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name).font(.caption.weight(.medium))
                                Text(model.desc).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.size).font(.caption2).foregroundStyle(.secondary)
                            Button("Pull") { onPull(model.name) }.font(.caption2).controlSize(.small)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }.frame(maxHeight: 200)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1)))
    }
}
