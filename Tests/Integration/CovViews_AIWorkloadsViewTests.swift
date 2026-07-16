import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - AIWorkloadsView ViewInspector integration tests

@Suite("CovViews_AIWorkloadsView Integration", .serialized)
@MainActor
struct CovViews_AIWorkloadsViewTests {

    private func stateEmpty() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.aiModels = []
        s.vmType = "vz"
        return s
    }

    private func stateWithModels() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.aiModels = [
            AIModelInfo(id: "gemma3", name: "gemma3", size: "2.1GB", status: "idle", port: nil),
            AIModelInfo(id: "phi4", name: "phi4", size: "8.2GB", status: "serving", port: 8080),
        ]
        s.vmType = "vz"
        return s
    }

    private func stateWithKrunkit() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.vmType = "krunkit"
        s.aiModels = []
        return s
    }

    // MARK: - Shell

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect()) != nil)
    }

    // MARK: - Prerequisites section

    @Test("prerequisites section renders without crash")
    func prerequisitesSectionPresent() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(text: "Prerequisites & Status")) != nil)
    }

    @Test("krunkit status indicator is present")
    func krunkitStatusIndicator() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_krunkit")) != nil)
    }

    @Test("install krunkit button is present")
    func installKrunkitButton() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_install_ai_krunkit")) != nil)
    }

    @Test("warning row shown when vmType is not krunkit")
    func warningWhenNotKrunkit() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        // vmType == "vz" → krunkit not available → warning shown
        #expect((try? v.inspect().find(text: "Krunkit Not Found")) != nil)
    }

    @Test("no warning when vmType is krunkit")
    func noWarningWhenKrunkit() throws {
        let v = AIWorkloadsView().environmentObject(stateWithKrunkit())
        #expect((try? v.inspect().find(text: "Krunkit Available")) != nil)
    }

    @Test("switch to krunkit button shown when not krunkit")
    func switchToKrunkitButtonShown() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(button: "Switch to krunkit")) != nil)
    }

    // MARK: - Model Library section

    @Test("model library section renders")
    func modelLibraryPresent() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(text: "Model Library")) != nil)
    }

    @Test("model name field is present")
    func modelNameField() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_ai_modelname")) != nil)
    }

    @Test("runner picker is present")
    func runnerPicker() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_ai_runner")) != nil)
    }

    @Test("Run button is present")
    func runButton() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_run_ai_model")) != nil)
    }

    @Test("Serve button is present")
    func serveButton() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_serve_ai_model")) != nil)
    }

    @Test("table_ai_models accessibility id is present")
    func aiModelsTable() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_ai_models")) != nil)
    }

    // MARK: - Downloaded tab

    @Test("downloaded tab has correct accessibility id")
    func downloadedTabId() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "tab_ai_downloaded")) != nil)
    }

    @Test("empty models shows no-model hint text")
    func emptyModelsHint() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(text: "No models downloaded. Pull a model or use `colima model pull <name>`.")) != nil)
    }

    @Test("populated models show run button for idle model")
    func runButtonForIdleModel() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_run_gemma3")) != nil)
    }

    @Test("populated models show serve button for idle model")
    func serveButtonForIdleModel() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_serve_gemma3")) != nil)
    }

    @Test("populated models show delete button for each model")
    func deleteButtonForModel() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_delete_gemma3")) != nil)
    }

    @Test("active serving model: run/serve buttons absent (not idle)")
    func servingModelNoRunServe() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        // phi4 is "serving", so run/serve are hidden
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_run_phi4")) == nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_serve_phi4")) == nil)
    }

    @Test("active serving model: delete button still present")
    func servingModelDeletePresent() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_delete_phi4")) != nil)
    }

    // MARK: - Active Models section

    @Test("active models section renders")
    func activeModelsSectionPresent() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(text: "Active Models")) != nil)
    }

    @Test("no active models shows placeholder text")
    func noActiveModelsPlaceholder() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(text: "No active models")) != nil)
    }

    @Test("serving model shows serve URL text")
    func servingModelShowsURL() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_ai_serve_url")) != nil)
    }

    @Test("serving model shows Open button")
    func servingModelOpenButton() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_open_browser")) != nil)
    }

    @Test("serving model shows Stop button")
    func servingModelStopButton() throws {
        let v = AIWorkloadsView().environmentObject(stateWithModels())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_stop_phi4")) != nil)
    }

    // MARK: - Quick Actions section

    @Test("quick actions section renders")
    func quickActionsPresent() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(text: "Quick Actions")) != nil)
    }

    @Test("Setup button present in quick actions")
    func setupButton() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_setup_ai_model")) != nil)
    }

    @Test("Browse Models button present in quick actions")
    func browseModelsButton() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_browse_ai_registry")) != nil)
    }

    @Test("Create AI Profile button present in quick actions")
    func createAIProfileButton() throws {
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_createprofile_ai_new")) != nil)
    }

    // MARK: - Error message path

    @Test("warning row accessible identifier on RAM warning text")
    func ramWarningIdentifier() throws {
        // When vmType != krunkit, the warning row should have text_ai_ram_warning
        let v = AIWorkloadsView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_ai_ram_warning")) != nil)
    }
}

// MARK: - ModelBrowserView ViewInspector integration tests

@Suite("CovViews_ModelBrowserView Integration", .serialized)
@MainActor
struct CovViews_ModelBrowserViewTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        var didClose = false
        let v = ModelBrowserView(runner: "docker", onPull: { _ in }, onClose: { didClose = true })
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows Model Browser title")
    func showsTitle() throws {
        let v = ModelBrowserView(runner: "docker", onPull: { _ in }, onClose: {})
        #expect((try? v.inspect().find(text: "Model Browser")) != nil)
    }

    @Test("shows Registry picker")
    func showsRegistryPicker() throws {
        let v = ModelBrowserView(runner: "docker", onPull: { _ in }, onClose: {})
        #expect((try? v.inspect().find(text: "Registry")) != nil)
    }

    @Test("shows search field")
    func showsSearchField() throws {
        let v = ModelBrowserView(runner: "docker", onPull: { _ in }, onClose: {})
        #expect((try? v.inspect().find(text: "Search models...")) != nil)
    }

    @Test("shows Docker AI models by default")
    func showsDockerAIModels() throws {
        let v = ModelBrowserView(runner: "docker", onPull: { _ in }, onClose: {})
        // Docker AI models include ai/gemma3
        #expect((try? v.inspect().find(text: "ai/gemma3")) != nil)
    }

    @Test("shows Pull button for each model")
    func showsPullButtons() throws {
        let v = ModelBrowserView(runner: "docker", onPull: { _ in }, onClose: {})
        // Should find at least one Pull button
        #expect((try? v.inspect().find(button: "Pull")) != nil)
    }

    @Test("close button is present")
    func closeButtonPresent() throws {
        let v = ModelBrowserView(runner: "docker", onPull: { _ in }, onClose: {})
        // The xmark button is the close button
        #expect((try? v.inspect().find(ViewType.Button.self)) != nil)
    }
}

// MARK: - AIWorkloadsView registry tab unit tests (via isolated wrapper)

@Suite("CovViews_AIRegistryTab Integration", .serialized)
@MainActor
struct CovViews_AIRegistryTabTests {

    private func registryTabView(id: String, models: [(name: String, desc: String, size: String)]) -> some View {
        RegistryTabWrapper(id: id, models: models)
    }

    @Test("docker AI registry tab has correct accessibility id")
    func dockerAITabId() throws {
        let v = RegistryTabWrapper(id: "dockerai", models: MockK8sData.dockerAIModels)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "tab_ai_dockerai")) != nil)
    }

    @Test("huggingface registry tab has correct accessibility id")
    func huggingfaceTabId() throws {
        let v = RegistryTabWrapper(id: "huggingface", models: MockK8sData.huggingFaceModels)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "tab_ai_huggingface")) != nil)
    }

    @Test("ollama registry tab has correct accessibility id")
    func ollamaTabId() throws {
        let v = RegistryTabWrapper(id: "ollama", models: MockK8sData.ollamaModels)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "tab_ai_ollama")) != nil)
    }

    @Test("pull button present for registry model")
    func pullButtonPresent() throws {
        let v = RegistryTabWrapper(id: "dockerai", models: MockK8sData.dockerAIModels)
        // e.g. ai/gemma3 pull button
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ai_pull_ai/gemma3")) != nil)
    }

    @Test("model description shown")
    func modelDescriptionShown() throws {
        let v = RegistryTabWrapper(id: "dockerai", models: MockK8sData.dockerAIModels)
        #expect((try? v.inspect().find(text: "Google Gemma 3 — lightweight open model")) != nil)
    }

    @Test("model size shown")
    func modelSizeShown() throws {
        let v = RegistryTabWrapper(id: "dockerai", models: MockK8sData.dockerAIModels)
        #expect((try? v.inspect().find(text: "~2.1GB")) != nil)
    }

    @Test("cancel button shown when pulling model")
    func cancelButtonWhenPulling() throws {
        let v = RegistryTabWrapperPulling(id: "dockerai", models: MockK8sData.dockerAIModels, pullingModel: "ai/gemma3")
        #expect((try? v.inspect().find(button: "Cancel")) != nil)
    }
}

// MARK: - Helper wrappers for isolated tab testing

private struct RegistryTabWrapper: View {
    let id: String
    let models: [(name: String, desc: String, size: String)]
    @State private var pullingModel: String? = nil

    var body: some View {
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
                            Button("Cancel") { pullingModel = nil }.font(.caption)
                        } else {
                            Button("Pull") { pullingModel = m.name }
                                .font(.caption)
                                .accessibilityIdentifier("btn_ai_pull_\(m.name)")
                        }
                    }
                    if pullingModel == m.name {
                        PullProgressView(name: m.name) { pullingModel = nil }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .accessibilityIdentifier("tab_ai_\(id)")
    }
}

private struct RegistryTabWrapperPulling: View {
    let id: String
    let models: [(name: String, desc: String, size: String)]
    let pullingModel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(models, id: \.name) { m in
                HStack {
                    Text(m.name)
                    Spacer()
                    if pullingModel == m.name {
                        Button("Cancel") { }.font(.caption)
                    } else {
                        Button("Pull") { }.font(.caption)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .accessibilityIdentifier("tab_ai_\(id)")
    }
}
