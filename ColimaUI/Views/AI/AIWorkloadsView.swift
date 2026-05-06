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
    @State private var showModelBrowser = false

    private var legacyQuickActions: some View {
        GroupBox("Quick Actions") {
            HStack(spacing: 8) {
                Button("Setup") { showSetupFlow = true }.accessibilityIdentifier("btn_setup_ai_model")
                Button("Browse Models") { showModelBrowser = true }.accessibilityIdentifier("btn_browse_ai_registry")
                Button("Create AI Profile") { appState.showToast("AI profile created") }.accessibilityIdentifier("btn_createprofile_ai_new")
            }

            if showSetupFlow {
                AISetupProgressView(runner: runner) { showSetupFlow = false }
            }

            if showModelBrowser {
                ModelBrowserView { showModelBrowser = false }
            }
        }
    }
}

// MARK: - Model Browser

struct ModelBrowserView: View {
    let onClose: () -> Void
    @State private var selectedRegistry = "Docker AI"
    @State private var searchText = ""
    @State private var pullingModel: String?

    private let registries = ["Docker AI", "HuggingFace", "Ollama"]

    private var models: [(name: String, desc: String, size: String, downloads: String, stars: Int, capabilities: [String])] {
        switch selectedRegistry {
        case "Docker AI":
            return [
                ("ai/gemma3", "Google's Gemma 3 — fast, efficient", "2.5 GB", "1.2M", 4850, ["Text Generation", "Chat"]),
                ("ai/llama3.2", "Meta's Llama 3.2 — versatile", "4.7 GB", "890K", 5200, ["Text Generation", "Code"]),
                ("ai/phi-4", "Microsoft Phi-4 — compact powerhouse", "2.3 GB", "650K", 3900, ["Text Generation", "Reasoning"]),
                ("ai/smollm2", "HuggingFace SmolLM2 — tiny & fast", "1.1 GB", "420K", 2100, ["Text Generation"]),
                ("ai/mistral", "Mistral 7B — balanced performance", "4.1 GB", "780K", 4600, ["Text Generation", "Code"]),
                ("ai/qwen2.5", "Alibaba Qwen 2.5 — multilingual", "4.5 GB", "560K", 3400, ["Text Generation", "Multilingual"]),
                ("ai/deepseek-r1", "DeepSeek R1 — reasoning focused", "8.2 GB", "340K", 4100, ["Reasoning", "Math"]),
                ("ai/codellama", "Meta Code Llama — code specialist", "3.8 GB", "920K", 4300, ["Code Generation", "Completion"]),
                ("ai/nomic-embed", "Nomic Embed — text embeddings", "0.5 GB", "280K", 1800, ["Embeddings"]),
                ("ai/whisper", "OpenAI Whisper — speech to text", "1.5 GB", "1.5M", 5100, ["Speech Recognition"]),
            ]
        case "HuggingFace":
            return [
                ("microsoft/Phi-3-mini-4k-instruct-gguf", "Phi-3 Mini GGUF", "2.4 GB", "3.2M", 8900, ["Text Generation"]),
                ("TheBloke/Llama-2-7B-GGUF", "Llama 2 7B quantized", "4.0 GB", "2.8M", 7200, ["Text Generation"]),
                ("sentence-transformers/all-MiniLM-L6-v2", "Sentence embeddings", "0.1 GB", "5.1M", 6800, ["Embeddings"]),
                ("openai/whisper-large-v3", "Whisper Large V3", "3.1 GB", "1.9M", 5400, ["Speech"]),
                ("stabilityai/stable-diffusion-xl", "SDXL image generation", "6.9 GB", "4.2M", 9100, ["Image Generation"]),
            ]
        default: // Ollama
            return [
                ("gemma3", "Google Gemma 3", "2.5 GB", "1.8M", 5600, ["Text Generation", "Chat"]),
                ("llama3.2", "Meta Llama 3.2", "4.7 GB", "2.1M", 6200, ["Text Generation", "Code"]),
                ("mistral", "Mistral 7B", "4.1 GB", "1.4M", 5100, ["Text Generation"]),
                ("codellama", "Code Llama", "3.8 GB", "980K", 4500, ["Code Generation"]),
                ("phi4", "Microsoft Phi-4", "2.3 GB", "720K", 3800, ["Reasoning"]),
            ]
        }
    }

    private var filteredModels: [(name: String, desc: String, size: String, downloads: String, stars: Int, capabilities: [String])] {
        guard !searchText.isEmpty else { return Array(models.prefix(10)) }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.desc.localizedCaseInsensitiveContains(searchText) ||
            $0.capabilities.joined().localizedCaseInsensitiveContains(searchText)
        }.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model Browser").font(.caption.weight(.semibold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.borderless)
            }

            // Registry picker
            Picker("Registry", selection: $selectedRegistry) {
                ForEach(registries, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            // Search
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            // Model list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filteredModels, id: \.name) { model in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).font(.caption.weight(.medium)).lineLimit(1)
                                Text(model.desc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                HStack(spacing: 6) {
                                    ForEach(model.capabilities, id: \.self) { cap in
                                        Text(cap)
                                            .font(.system(size: 9))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                                    Text("\(model.stars)").font(.caption2)
                                }
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down.circle").font(.system(size: 8)).foregroundStyle(.secondary)
                                    Text(model.downloads).font(.caption2)
                                }
                                Text(model.size).font(.caption2).foregroundStyle(.secondary)
                            }
                            if pullingModel == model.name {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Pull") { pullingModel = model.name }
                                    .font(.caption2)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 250)

            if let pulling = pullingModel {
                PullProgressView(name: pulling) { pullingModel = nil }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1)))
    }
}
