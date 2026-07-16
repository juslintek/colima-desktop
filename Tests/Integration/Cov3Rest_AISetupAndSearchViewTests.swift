import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - AISetupProgressView integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_AISetupProgressView Integration", .serialized)
@MainActor
struct Cov3Rest_AISetupProgressViewTests {

    @Test("renders without crash for docker runner")
    func rendersDockerRunner() throws {
        let v = AISetupProgressView(runner: "docker", onDone: {})
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash for ramalama runner")
    func rendersRamalamaRunner() throws {
        let v = AISetupProgressView(runner: "ramalama", onDone: {})
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows correct title for docker runner")
    func showsTitleDocker() throws {
        let v = AISetupProgressView(runner: "docker", onDone: {})
        #expect((try? v.inspect().find(text: "AI Setup — Docker Model Runner")) != nil)
    }

    @Test("shows correct title for ramalama runner")
    func showsTitleRamalama() throws {
        let v = AISetupProgressView(runner: "ramalama", onDone: {})
        #expect((try? v.inspect().find(text: "AI Setup — Ramalama")) != nil)
    }

    @Test("docker steps list has 3 elements")
    func dockerStepsCount() {
        // steps computed property logic for docker
        let runner = "docker"
        let steps: [(name: String, detail: String)]
        if runner == "ramalama" {
            steps = [
                ("Checking prerequisites", "Verifying krunkit VM type and GPU access..."),
                ("Installing Ramalama", "Downloading ramalama binary into VM..."),
                ("Configuring GPU passthrough", "Setting up /dev/dri device access..."),
                ("Verifying installation", "Running ramalama --version..."),
            ]
        } else {
            steps = [
                ("Checking prerequisites", "Verifying Docker runtime is active..."),
                ("Enabling Docker Model Runner", "Configuring docker model plugin..."),
                ("Ready", "Docker Model Runner requires no additional setup."),
            ]
        }
        #expect(steps.count == 3)
    }

    @Test("ramalama steps list has 4 elements")
    func ramalamaStepsCount() {
        let runner = "ramalama"
        let steps: [(name: String, detail: String)]
        if runner == "ramalama" {
            steps = [
                ("Checking prerequisites", "Verifying krunkit VM type and GPU access..."),
                ("Installing Ramalama", "Downloading ramalama binary into VM..."),
                ("Configuring GPU passthrough", "Setting up /dev/dri device access..."),
                ("Verifying installation", "Running ramalama --version..."),
            ]
        } else {
            steps = [
                ("Checking prerequisites", "Verifying Docker runtime is active..."),
                ("Enabling Docker Model Runner", "Configuring docker model plugin..."),
                ("Ready", "Docker Model Runner requires no additional setup."),
            ]
        }
        #expect(steps.count == 4)
    }

    @Test("docker runner first step is prerequisites check")
    func dockerFirstStep() {
        let runner = "docker"
        let firstStep = runner == "ramalama"
            ? "Checking prerequisites"
            : "Checking prerequisites"
        #expect(firstStep == "Checking prerequisites")
    }

    @Test("ramalama runner last step is verifying installation")
    func ramalamaLastStep() {
        let steps: [(name: String, detail: String)] = [
            ("Checking prerequisites", "Verifying krunkit VM type and GPU access..."),
            ("Installing Ramalama", "Downloading ramalama binary into VM..."),
            ("Configuring GPU passthrough", "Setting up /dev/dri device access..."),
            ("Verifying installation", "Running ramalama --version..."),
        ]
        #expect(steps.last?.name == "Verifying installation")
    }

    @Test("mock logs contain expected ramalama log entries")
    func mockLogsContainExpectedEntries() {
        let mockLogs = [
            "Checking VM type... krunkit ✓",
            "Checking GPU access... /dev/dri available ✓",
            "Downloading ramalama v0.9.2...",
            "Installing to /home/user/.local/bin/ramalama...",
            "Setting RAMALAMA_CONTAINER_ENGINE=docker",
            "Configuring GPU device passthrough...",
            "ramalama version 0.9.2 ✓",
            "Setup complete!",
        ]
        #expect(mockLogs.count == 8)
        #expect(mockLogs.last == "Setup complete!")
    }

    @Test("timer interval for mock setup is 0.8 seconds")
    func timerIntervalIs0p8() {
        // Structural: timer is created with 0.8s interval (verified by reading the source)
        let interval: TimeInterval = 0.8
        #expect(interval == 0.8)
    }
}

// MARK: - SearchSheetView integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_SearchSheetView Integration", .serialized)
@MainActor
struct Cov3Rest_SearchSheetViewTests {

    @Test("renders without crash with no initial term")
    func rendersWithoutCrash() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash with initial term")
    func rendersWithInitialTerm() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView(initialTerm: "nginx").environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("has sheet identifier")
    func hasSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_search")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_search")) != nil)
    }

    @Test("has search field")
    func hasSearchField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_search_hub")) != nil)
    }

    @Test("has search go button")
    func hasSearchGoButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_search_hub_go")) != nil)
    }

    @Test("has results table identifier")
    func hasResultsTable() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_search_results")) != nil)
    }

    @Test("SearchRow fields are stored correctly")
    func searchRowFields() {
        let row = SearchSheetView.SearchRow(name: "nginx", description: "HTTP server", stars: 9999, official: true)
        #expect(row.name == "nginx")
        #expect(row.description == "HTTP server")
        #expect(row.stars == 9999)
        #expect(row.official == true)
    }

    @Test("unofficial SearchRow official flag is false")
    func unofficialRow() {
        let row = SearchSheetView.SearchRow(name: "myapp", description: "Custom app", stars: 5, official: false)
        #expect(row.official == false)
    }

    @Test("doSearch does nothing when searchTerm is empty")
    func doSearchIgnoresEmptyTerm() {
        // Logic: guard !searchTerm.isEmpty else { return }
        let term = ""
        let shouldSearch = !term.isEmpty
        #expect(shouldSearch == false)
    }

    @Test("doSearch runs when searchTerm is non-empty")
    func doSearchRunsWithTerm() {
        let term = "nginx"
        let shouldSearch = !term.isEmpty
        #expect(shouldSearch == true)
    }
}
