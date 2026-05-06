import SwiftUI

struct AIWorkloadsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedModel = "gemma3"
    @State private var runner = "docker"
    @State private var krunkitAvailable = true
    @State private var selectedTab = 0
    @State private var vmType = "qemu"
    @State private var vmRAM = 8
    @State private var pullingModel: String?

    private let tabNames = ["Downloaded", "Docker AI", "HuggingFace", "Ollama"]

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
                if vmType != "krunkit" {
                    warningRow("VM type is '\(vmType)'. krunkit recommended for AI workloads.") {
                        Button("Switch to krunkit") { vmType = "krunkit"; appState.showToast("Switched to krunkit") }.font(.caption)
                    }
                }
                if let m = MockK8sData.aiModels.first(where: { $0.name == selectedModel }), m.requiredRAM > vmRAM {
                    warningRow("Model requires \(m.requiredRAM)GB RAM, VM has \(vmRAM)GB.", color: .red) { EmptyView() }
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
                    Button("Run") { appState.showToast("Model '\(selectedModel)' running") }
                        .accessibilityIdentifier("btn_run_ai_model")
                    Button("Serve") { appState.showToast("Model '\(selectedModel)' serving") }
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
            ForEach(MockK8sData.aiModels, id: \.name) { model in
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.name).fontWeight(.medium)
                        Text("\(model.size) • \(model.registry) • \(model.status)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.status == "idle" {
                        Button("Run") { appState.showToast("Model '\(model.name)' running") }
                            .font(.caption).accessibilityIdentifier("btn_ai_run_\(model.name)")
                        Button("Serve") { appState.showToast("Model '\(model.name)' serving") }
                            .font(.caption).accessibilityIdentifier("btn_ai_serve_\(model.name)")
                    }
                    Button("Delete") { appState.showToast("Deleted \(model.name)") }
                        .foregroundStyle(.red).font(.caption).accessibilityIdentifier("btn_ai_delete_\(model.name)")
                }
                .padding(.vertical, 4)
                Divider()
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
                            Button("Pull") { pullingModel = m.name }
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
            let active = MockK8sData.aiModels.filter { $0.status != "idle" }
            if active.isEmpty {
                Text("No active models").foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(active, id: \.name) { model in
                    HStack {
                        Circle().fill(model.status == "serving" ? .green : .blue).frame(width: 8, height: 8)
                        Text(model.name).fontWeight(.medium)
                        Text("(\(model.size))").foregroundStyle(.secondary)
                        Spacer()
                        if model.status == "serving", let port = model.port {
                            Text("http://localhost:\(port)")
                                .font(.system(.caption, design: .monospaced))
                                .accessibilityIdentifier("text_ai_serve_url")
                            Button("Open") { appState.showToast("Opening browser") }
                                .font(.caption).accessibilityIdentifier("btn_ai_open_browser")
                        }
                        Button("Stop") { appState.showToast("Stopped \(model.name)") }
                            .foregroundStyle(.red).font(.caption).accessibilityIdentifier("btn_ai_stop_\(model.name)")
                    }
                }
            }
        }
    }

    @State private var showSetupFlow = false

    private var legacyQuickActions: some View {
        GroupBox("Quick Actions") {
            HStack(spacing: 8) {
                Button("Setup") { showSetupFlow = true }.accessibilityIdentifier("btn_setup_ai_model")
                Button("Browse Models") { appState.showToast("Opening model browser") }.accessibilityIdentifier("btn_browse_ai_registry")
                Button("Create AI Profile") { appState.showToast("AI profile created") }.accessibilityIdentifier("btn_createprofile_ai_new")
            }

            if showSetupFlow {
                AISetupProgressView(runner: runner) { showSetupFlow = false }
            }
        }
    }
}
