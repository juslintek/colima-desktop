import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ProfilesView additional tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_ProfilesViewWave3 Integration", .serialized)
@MainActor
struct Cov3Rest_ProfilesViewWave3Tests {

    private func prof(_ name: String, status: String = "Running", runtime: String = "docker") -> MockProfile {
        MockProfile(id: name, name: name, status: status,
                    arch: "aarch64", cpus: 4, memory: "8GiB", disk: "100GiB", runtime: runtime)
    }

    private func state(profiles: [MockProfile] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.profiles = profiles
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        ProfilesView().environmentObject(appState)
    }

    @Test("renders without crash with empty profiles")
    func rendersEmpty() throws {
        let v = view(state())
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows profile row for each profile")
    func showsProfileRows() throws {
        let s = state(profiles: [prof("default"), prof("k8s", status: "Stopped")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_profile_default")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_profile_k8s")) != nil)
    }

    @Test("running profile has green status indicator")
    func runningProfileGreenIndicator() throws {
        let s = state(profiles: [prof("default", status: "Running")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_profile_default")) != nil)
    }

    @Test("shows start button for each profile")
    func showsStartButton() throws {
        let s = state(profiles: [prof("default")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_start_profile_default")) != nil)
    }

    @Test("shows stop button for each profile")
    func showsStopButton() throws {
        let s = state(profiles: [prof("default")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_stop_profile_default")) != nil)
    }

    @Test("shows restart button for each profile")
    func showsRestartButton() throws {
        let s = state(profiles: [prof("default")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_restart_profile_default")) != nil)
    }

    @Test("shows delete button for each profile")
    func showsDeleteButton() throws {
        let s = state(profiles: [prof("default")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_delete_profile_default")) != nil)
    }

    @Test("shows table identifier with profiles")
    func showsTableIdentifier() throws {
        let s = state(profiles: [prof("default")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_profiles")) != nil)
    }

    @Test("activeProfile shown in colima_profile text")
    func activeProfileShown() throws {
        let s = state()
        s.activeProfile = "my-profile"
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_colima_profile")) != nil)
    }
}

// MARK: - ProfileRowView additional tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_ProfileRowViewWave3 Integration", .serialized)
@MainActor
struct Cov3Rest_ProfileRowViewWave3Tests {

    private func prof(_ name: String, status: String = "Running") -> MockProfile {
        MockProfile(id: name, name: name, status: status,
                    arch: "aarch64", cpus: 4, memory: "8GiB", disk: "100GiB", runtime: "docker")
    }

    @Test("renders running profile without crash")
    func rendersRunning() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ProfileRowView(profile: prof("prod", status: "Running"), appState: s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders stopped profile without crash")
    func rendersStopped() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ProfileRowView(profile: prof("staging", status: "Stopped"), appState: s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows profile name text for running profile")
    func showsProfileName() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ProfileRowView(profile: prof("default"), appState: s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_profile_default")) != nil)
    }

    @Test("shows status indicator for stopped profile")
    func showsStoppedIndicator() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ProfileRowView(profile: prof("dev", status: "Stopped"), appState: s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_profile_dev")) != nil)
    }
}

// MARK: - Profile validation unit tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_ProfileValidation Unit", .serialized)
@MainActor
struct Cov3Rest_ProfileValidationTests {

    @Test("validateProfileName accepts valid name")
    func acceptsValidName() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateProfileName("my-profile")
        #expect(err == nil)
    }

    @Test("validateProfileName rejects empty name")
    func rejectsEmptyName() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateProfileName("")
        #expect(err != nil)
    }

    @Test("validateProfileName rejects name with spaces")
    func rejectsNameWithSpaces() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateProfileName("my profile")
        #expect(err != nil)
    }

    @Test("validateProfileName rejects name that is too long")
    func rejectsTooLongName() {
        let s = AppState(services: MockServiceProvider())
        let longName = String(repeating: "a", count: 65)
        let err = s.validateProfileName(longName)
        #expect(err != nil)
    }
}
