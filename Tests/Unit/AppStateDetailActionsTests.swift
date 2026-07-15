import Testing
import Foundation
@testable import ColimaDesktopKit

@MainActor
@Suite("AppState detail + profile actions", .serialized)
struct AppStateDetailActionsTests {

    private func newState() -> AppState { AppState(services: MockServiceProvider()) }

    private func awaitSheet(_ st: AppState, timeout: TimeInterval = 3) async -> AppState.SheetType? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let s = st.activeSheet { return s }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return st.activeSheet
    }
    private func awaitToast(_ st: AppState, timeout: TimeInterval = 3) async -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if st.isToastVisible { return st.toastMessage }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return st.toastMessage
    }

    // sync sheet-openers
    @Test("exec/top/stats/changes/attach/copy open the right sheets")
    func syncSheets() {
        var st = newState(); st.execContainer(name: "c"); #expect(st.activeSheet == .terminal); #expect(st.sheetEntityName == "c")
        st = newState(); st.topContainer(name: "c"); #expect(st.activeSheet == .stats)
        st = newState(); st.statsContainer(name: "c"); #expect(st.activeSheet == .stats)
        st = newState(); st.changesContainer(name: "c"); #expect(st.activeSheet == .changes)
        st = newState(); st.attachContainer(name: "c"); #expect(st.activeSheet == .terminal)
        st = newState(); st.copyContainer(name: "c"); #expect(st.activeSheet == .copyFiles)
    }

    @Test("wait + updateResources toast")
    func syncToasts() {
        let st = newState(); st.waitContainer(name: "c"); #expect(st.isToastVisible)
        let s2 = newState(); s2.updateContainerResources(name: "c"); #expect(s2.isToastVisible)
    }

    // async sheet-openers
    @Test("logs opens logs sheet")
    func logsSheet() async {
        let st = newState(); st.logsContainer(name: "web-server")
        #expect(await awaitSheet(st) == .logs)
        #expect(!st.sheetLogs.isEmpty || st.sheetEntityName == "web-server")
    }

    @Test("inspect container opens inspect sheet with content")
    func inspectContainerSheet() async {
        let st = newState(); st.inspectContainer(name: "web-server")
        #expect(await awaitSheet(st) == .inspect)
        #expect(!st.sheetContent.isEmpty)
    }

    @Test("inspect image/volume/network open a sheet")
    func inspectResources() async {
        let s1 = newState(); s1.inspectImage(repo: "nginx"); #expect(await awaitSheet(s1) != nil)
        let s2 = newState(); s2.inspectVolume(name: "postgres_data"); #expect(await awaitSheet(s2) != nil)
        let s3 = newState(); s3.inspectNetwork(name: "bridge"); #expect(await awaitSheet(s3) != nil)
    }

    // remove actions
    @Test("remove image/volume/network toast")
    func removeActions() async {
        let s1 = newState(); s1.removeImage(id: "sha256:abc"); #expect(await awaitToast(s1) != nil)
        let s2 = newState(); s2.removeVolume(name: "postgres_data"); #expect(await awaitToast(s2) != nil)
        let s3 = newState(); s3.removeNetwork(name: "app-net"); #expect(await awaitToast(s3) != nil)
    }

    @Test("network connect/disconnect toast")
    func networkConnectivity() async {
        let s1 = newState(); s1.connectNetwork(network: "bridge", container: "web-server"); #expect(await awaitToast(s1) != nil)
        let s2 = newState(); s2.disconnectNetwork(network: "bridge", container: "web-server"); #expect(await awaitToast(s2) != nil)
    }

    // profile lifecycle
    @Test("profile start/stop/restart/delete/clone toast")
    func profileLifecycle() async {
        let s1 = newState(); s1.startProfile(name: "default"); #expect((await awaitToast(s1))?.contains("started") == true)
        let s2 = newState(); s2.stopProfile(name: "default"); #expect((await awaitToast(s2))?.contains("stopped") == true)
        let s3 = newState(); s3.restartProfile(name: "default"); #expect((await awaitToast(s3))?.contains("restarted") == true)
        let s4 = newState(); s4.deleteProfile(name: "default"); #expect((await awaitToast(s4))?.contains("deleted") == true)
        let s5 = newState(); s5.cloneProfile(source: "default", dest: "clone1"); #expect((await awaitToast(s5))?.contains("cloned") == true)
    }

    // validation edge cases
    @Test("validators reject bad and accept good names")
    func validators() {
        let st = newState()
        #expect(st.validateProfileName("") != nil)
        #expect(st.validateProfileName("ok-name") == nil)
        #expect(st.validateImageName("") != nil)
        #expect(st.validateNetworkName("") != nil)
        #expect(st.validateVolumeName("good_vol") == nil)
    }
}
