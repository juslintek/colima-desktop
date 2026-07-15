import Testing
import Foundation
@testable import ColimaDesktopKit

@MainActor
@Suite("AppState actions", .serialized)
struct AppStateActionsTests {

    private func newState() -> AppState { AppState(services: MockServiceProvider()) }

    /// Wait until a toast becomes visible (fire-and-forget actions run on the main actor).
    private func awaitToast(_ st: AppState, timeout: TimeInterval = 3) async -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if st.isToastVisible { return st.toastMessage }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return st.toastMessage
    }

    // MARK: sync helpers

    @Test("showToast sets message + visible")
    func showToast() {
        let st = newState()
        st.showToast("hello")
        #expect(st.toastMessage == "hello")
        #expect(st.isToastVisible)
    }

    @Test("showError prefixes warning + records errorMessage")
    func showError() {
        let st = newState()
        st.showError("boom")
        #expect(st.errorMessage == "boom")
        #expect(st.toastMessage?.contains("boom") == true)
    }

    @Test("requiresVM gates on vmRunning")
    func requiresVM() {
        let st = newState()
        st.vmRunning = true
        #expect(st.requiresVM("X"))
        st.vmRunning = false
        #expect(!st.requiresVM("X"))
        #expect(st.errorMessage?.contains("not running") == true)
    }

    @Test("requestConfirmation stores message + action")
    func requestConfirmation() {
        let st = newState()
        var ran = false
        st.requestConfirmation("sure?") { ran = true }
        #expect(st.showConfirmation)
        #expect(st.confirmationMessage == "sure?")
        st.confirmationAction?()
        #expect(ran)
    }

    // MARK: refresh

    @Test("refresh* populate their lists from the mock backend")
    func refreshPopulates() async {
        let st = newState()
        await st.refreshContainers(); #expect(!st.containers.isEmpty)
        await st.refreshImages();     #expect(!st.images.isEmpty)
        await st.refreshVolumes();    #expect(!st.volumes.isEmpty)
        await st.refreshNetworks();   #expect(!st.networks.isEmpty)
        await st.refreshProfiles();   #expect(!st.profiles.isEmpty)
        await st.refreshMachines();   #expect(!st.machines.isEmpty)
    }

    @Test("refreshAll runs without throwing")
    func refreshAll() async {
        let st = newState()
        await st.refreshAll()
        #expect(st.colimaInstalled)
    }

    // MARK: VM lifecycle

    @Test("startVM → running + toast")
    func startVM() async {
        let st = newState(); st.startVM()
        #expect((await awaitToast(st))?.contains("started") == true)
        #expect(st.vmRunning)
    }

    @Test("stopVM → stopped + toast")
    func stopVM() async {
        let st = newState(); st.stopVM()
        #expect((await awaitToast(st))?.contains("stopped") == true)
        #expect(!st.vmRunning)
    }

    @Test("restartVM → toast")
    func restartVM() async {
        let st = newState(); st.restartVM()
        #expect((await awaitToast(st))?.contains("restarted") == true)
    }

    @Test("deleteVM hard clears lists")
    func deleteVM() async {
        let st = newState()
        await st.refreshContainers()
        st.deleteVM(hard: true)
        _ = await awaitToast(st)
        #expect(!st.vmRunning)
        #expect(st.containers.isEmpty)
    }

    // MARK: container actions

    @Test("container lifecycle actions all toast")
    func containerActions() async {
        for (action, verb): ((AppState, String) -> Void, String) in [
            ({ $0.startContainer(name: $1) }, "started"),
            ({ $0.stopContainer(name: $1) }, "stopped"),
            ({ $0.killContainer(name: $1) }, "killed"),
            ({ $0.restartContainer(name: $1) }, "restarted"),
            ({ $0.pauseContainer(name: $1) }, "paused"),
            ({ $0.unpauseContainer(name: $1) }, "unpaused"),
            ({ $0.removeContainer(name: $1) }, "removed"),
        ] {
            let st = newState()
            action(st, "web-server")
            let toast = await awaitToast(st)
            #expect(toast != nil, "action \(verb) produced no toast")
        }
    }

    @Test("createContainer + rename + prune toast")
    func containerCreateRenamePrune() async {
        let st = newState()
        st.createContainer(name: "newc", image: "nginx:latest")
        #expect(await awaitToast(st) != nil)
        let st2 = newState()
        st2.pruneContainers()
        #expect(await awaitToast(st2) != nil)
    }

    // MARK: image actions

    @Test("image actions toast")
    func imageActions() async {
        let st = newState(); st.pullImage(name: "redis:7"); #expect(await awaitToast(st) != nil)
        let s2 = newState(); s2.pruneImages(); #expect(await awaitToast(s2) != nil)
        let s3 = newState(); s3.tagImage(repo: "nginx", newTag: "v2"); #expect(await awaitToast(s3) != nil)
    }

    // MARK: volume + network actions

    @Test("volume actions toast")
    func volumeActions() async {
        let st = newState(); st.createVolume(name: "vol1"); #expect(await awaitToast(st) != nil)
        let s2 = newState(); s2.pruneVolumes(); #expect(await awaitToast(s2) != nil)
    }

    @Test("network actions toast")
    func networkActions() async {
        let st = newState(); st.createNetwork(name: "net1"); #expect(await awaitToast(st) != nil)
        let s2 = newState(); s2.pruneNetworks(); #expect(await awaitToast(s2) != nil)
    }

    // MARK: profile actions

    @Test("profile create + lifecycle toast")
    func profileActions() async {
        let st = newState()
        st.createProfile(name: "p1", cpus: 2, memory: "4GiB", runtime: "docker")
        #expect(await awaitToast(st) != nil)
    }

    // MARK: system

    @Test("updateColima + pruneSystem toast")
    func systemActions() async {
        let st = newState(); st.updateColima(); #expect(await awaitToast(st) != nil)
        let s2 = newState(); s2.pruneColima(all: true); #expect(await awaitToast(s2) != nil)
    }

    @Test("switchProfile updates active profile")
    func switchProfile() async {
        let st = newState()
        await st.switchProfile(name: "default")
        #expect(st.activeProfile == "default")
    }
}
