import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ProfilesView integration tests

@Suite("ProfilesView Integration", .serialized)
@MainActor
struct ProfilesViewTests {

    private func state(profiles: [MockProfile] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.profiles = profiles
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        ProfilesView().environmentObject(appState)
    }

    private func prof(_ name: String, status: String = "Running") -> MockProfile {
        MockProfile(id: name, name: name, status: status, arch: "aarch64", cpus: 4, memory: "8GiB", disk: "100GiB", runtime: "docker")
    }

    @Test("shows active profile text")
    func showsActiveProfile() throws {
        let s = state()
        s.activeProfile = "default"
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_colima_profile")) != nil)
    }

    @Test("shows colima home text")
    func showsColimaHome() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_colima_home")) != nil)
    }

    @Test("has create profile button")
    func createProfileButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_profile_new")) != nil)
    }

    @Test("has clone profile button")
    func cloneProfileButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_clone_profile_selected")) != nil)
    }

    @Test("shows profile list with profiles")
    func profileList() throws {
        let s = state(profiles: [prof("default"), prof("dev")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_profiles")) != nil)
    }

    @Test("shows profile names in list")
    func profileNames() throws {
        let s = state(profiles: [prof("default"), prof("k8s")])
        let v = view(s)
        #expect((try? v.inspect().find(text: "default")) != nil)
        #expect((try? v.inspect().find(text: "k8s")) != nil)
    }
}

// MARK: - ResourceAdvisor.Recommendation.Severity

@Suite("ResourceAdvisor.Recommendation.Severity")
struct RecommendationSeverityTests {

    @Test("info severity uses blue color")
    func infoColor() {
        let sev = ResourceAdvisor.Recommendation.Severity.info
        #expect(sev.color == .blue)
    }

    @Test("warning severity uses orange color")
    func warningColor() {
        let sev = ResourceAdvisor.Recommendation.Severity.warning
        #expect(sev.color == .orange)
    }

    @Test("critical severity uses red color")
    func criticalColor() {
        let sev = ResourceAdvisor.Recommendation.Severity.critical
        #expect(sev.color == .red)
    }
}

// MARK: - ResourceAdvisor.Recommendation struct

@Suite("ResourceAdvisor.Recommendation")
struct RecommendationTests {

    @Test("stores all fields correctly")
    func fieldsStored() {
        let rec = ResourceAdvisor.Recommendation(
            icon: "battery.25",
            severity: .warning,
            title: "Low Power",
            detail: "Reduce allocation",
            action: "Adjust config"
        )
        #expect(rec.icon == "battery.25")
        #expect(rec.severity == .warning)
        #expect(rec.title == "Low Power")
        #expect(rec.detail == "Reduce allocation")
        #expect(rec.action == "Adjust config")
    }

    @Test("each recommendation has a unique id")
    func uniqueId() {
        let a = ResourceAdvisor.Recommendation(icon: "x", severity: .info, title: "t", detail: "d", action: "a")
        let b = ResourceAdvisor.Recommendation(icon: "x", severity: .info, title: "t", detail: "d", action: "a")
        #expect(a.id != b.id)
    }
}

// MARK: - ResourceAdvisor view tests

@Suite("ResourceAdvisor Integration", .serialized)
@MainActor
struct ResourceAdvisorTests {

    @Test("renders nothing when VM is not running")
    func vmNotRunning() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = false
        let v = ResourceAdvisor().environmentObject(s)
        // When no recommendations, the view renders an empty body.
        // GroupBox should not be present.
        let hasGroupBox = (try? v.inspect().find(ViewType.GroupBox.self)) != nil
        #expect(!hasGroupBox)
    }

    @Test("shows idle recommendation when VM running with no containers")
    func idleRecommendation() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.containers = []
        s.vmCPU = 4
        s.vmMemory = Int64(8 * 1_073_741_824)
        let v = ResourceAdvisor().environmentObject(s)
        // Should show "No containers running" recommendation
        #expect((try? v.inspect().find(text: "No containers running")) != nil)
    }
}
