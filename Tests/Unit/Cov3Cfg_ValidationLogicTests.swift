import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - Cov3Cfg_ prefix · Validation logic unit tests (wave 3)
// Covers pure logic paths in AppState validation helpers and ColimaConfig
// that are NOT covered by CovConfig_ or CovRest_ unit suites.
// No view rendering — pure Swift Testing @Test functions.

@MainActor
private func makeState() -> AppState { AppState(services: MockServiceProvider()) }

// ─── validateVolumeName branches ─────────────────────────────────────────────

@Suite("Cov3Cfg_ValidateVolumeName", .serialized)
@MainActor
struct Cov3Cfg_ValidateVolumeName {

    @Test("empty volume name returns error")
    func emptyVolumeNameError() {
        let s = makeState()
        #expect(s.validateVolumeName("") != nil)
    }

    @Test("valid alphanumeric volume name passes")
    func validAlphanumericVolume() {
        let s = makeState()
        #expect(s.validateVolumeName("my-volume_01") == nil)
    }

    @Test("volume name with dots passes")
    func volumeNameWithDots() {
        let s = makeState()
        #expect(s.validateVolumeName("vol.data.v2") == nil)
    }

    @Test("volume name with spaces fails")
    func volumeNameWithSpaces() {
        let s = makeState()
        #expect(s.validateVolumeName("my volume") != nil)
    }

    @Test("volume name with special chars fails")
    func volumeNameWithSpecialChars() {
        let s = makeState()
        #expect(s.validateVolumeName("vol!data") != nil)
    }
}

// ─── validateNetworkName branches ────────────────────────────────────────────

@Suite("Cov3Cfg_ValidateNetworkName", .serialized)
@MainActor
struct Cov3Cfg_ValidateNetworkName {

    @Test("empty network name returns error")
    func emptyNetworkNameError() {
        let s = makeState()
        #expect(s.validateNetworkName("") != nil)
    }

    @Test("valid alphanumeric network name passes")
    func validAlphanumericNetwork() {
        let s = makeState()
        #expect(s.validateNetworkName("my-bridge_01") == nil)
    }

    @Test("network name with dots passes")
    func networkNameWithDots() {
        let s = makeState()
        #expect(s.validateNetworkName("net.internal.01") == nil)
    }

    @Test("network name with slashes fails")
    func networkNameWithSlashes() {
        let s = makeState()
        #expect(s.validateNetworkName("my/network") != nil)
    }

    @Test("network name with spaces fails")
    func networkNameWithSpaces() {
        let s = makeState()
        #expect(s.validateNetworkName("my network") != nil)
    }
}

// ─── validateProfileName branches ────────────────────────────────────────────

@Suite("Cov3Cfg_ValidateProfileName", .serialized)
@MainActor
struct Cov3Cfg_ValidateProfileName {

    @Test("empty profile name returns error")
    func emptyProfileNameError() {
        let s = makeState()
        #expect(s.validateProfileName("") != nil)
    }

    @Test("valid profile name passes")
    func validProfileName() {
        let s = makeState()
        #expect(s.validateProfileName("dev-profile_01") == nil)
    }

    @Test("profile name exceeding 64 chars returns error")
    func profileNameTooLong() {
        let s = makeState()
        let long = String(repeating: "a", count: 65)
        #expect(s.validateProfileName(long) != nil)
    }

    @Test("profile name exactly 64 chars passes")
    func profileNameExactly64() {
        let s = makeState()
        let exact = String(repeating: "a", count: 64)
        #expect(s.validateProfileName(exact) == nil)
    }

    @Test("profile name with spaces fails")
    func profileNameWithSpaces() {
        let s = makeState()
        #expect(s.validateProfileName("my profile") != nil)
    }

    @Test("profile name with at-sign fails")
    func profileNameWithAtSign() {
        let s = makeState()
        #expect(s.validateProfileName("profile@01") != nil)
    }
}

// ─── validateImageName extra branches ────────────────────────────────────────

@Suite("Cov3Cfg_ValidateImageNameExtra", .serialized)
@MainActor
struct Cov3Cfg_ValidateImageNameExtra {

    @Test("image with uppercase repo passes")
    func imageWithUppercaseRepo() {
        let s = makeState()
        // Docker Hub allows uppercase in practice but our regex covers A-Za-z at start
        #expect(s.validateImageName("MyImage:latest") == nil)
    }

    @Test("image with version tag passes")
    func imageWithVersionTag() {
        let s = makeState()
        #expect(s.validateImageName("ubuntu:22.04") == nil)
    }

    @Test("image with hyphen in repo passes")
    func imageWithHyphenRepo() {
        let s = makeState()
        #expect(s.validateImageName("my-app:v1") == nil)
    }

    @Test("image name starting with digit passes")
    func imageNameStartingWithDigit() {
        // Our regex allows [a-zA-Z0-9] at start
        let s = makeState()
        #expect(s.validateImageName("3rdparty/tool:latest") == nil)
    }

    @Test("image with path segments passes")
    func imageWithPathSegments() {
        let s = makeState()
        #expect(s.validateImageName("myregistry.io/team/service:v2") == nil)
    }
}

// ─── ColimaConfig default values ─────────────────────────────────────────────

@Suite("Cov3Cfg_ColimaConfigDefaults", .serialized)
struct Cov3Cfg_ColimaConfigDefaults {

    @Test("default cpu is 2")
    func defaultCpu() {
        let c = ColimaConfig()
        #expect(c.cpu == 2)
    }

    @Test("default vmType is vz")
    func defaultVmType() {
        let c = ColimaConfig()
        #expect(c.vmType == "vz")
    }

    @Test("default arch is aarch64")
    func defaultArch() {
        let c = ColimaConfig()
        #expect(c.arch == "aarch64")
    }

    @Test("default kubernetes enabled is false")
    func defaultK8sEnabled() {
        let c = ColimaConfig()
        #expect(c.kubernetes.enabled == false)
    }

    @Test("default network mode is shared")
    func defaultNetworkMode() {
        let c = ColimaConfig()
        #expect(c.network.mode == "shared")
    }

    @Test("default mounts is empty array")
    func defaultMountsEmpty() {
        let c = ColimaConfig()
        #expect(c.mounts.isEmpty)
    }

    @Test("default provision is empty array")
    func defaultProvisionEmpty() {
        let c = ColimaConfig()
        #expect(c.provision.isEmpty)
    }

    @Test("default env is empty dict")
    func defaultEnvEmpty() {
        let c = ColimaConfig()
        #expect(c.env.isEmpty)
    }

    @Test("Mount struct stores location and writable correctly")
    func mountStruct() {
        let m = ColimaConfig.Mount(location: "~/projects", writable: true)
        #expect(m.location == "~/projects")
        #expect(m.writable == true)
    }

    @Test("Provision struct stores mode and script correctly")
    func provisionStruct() {
        let p = ColimaConfig.Provision(mode: "user", script: "echo test")
        #expect(p.mode == "user")
        #expect(p.script == "echo test")
    }

    @Test("KubernetesConfig stores version correctly")
    func kubernetesVersionStored() {
        var c = ColimaConfig()
        c.kubernetes.version = "v1.31.4+k3s1"
        #expect(c.kubernetes.version == "v1.31.4+k3s1")
    }

    @Test("NetworkConfig dns array stores multiple entries")
    func networkDNSArray() {
        var c = ColimaConfig()
        c.network.dns = ["1.1.1.1", "8.8.8.8"]
        #expect(c.network.dns.count == 2)
        #expect(c.network.dns[0] == "1.1.1.1")
    }
}

// ─── AppState.requiresVM ──────────────────────────────────────────────────────

@Suite("Cov3Cfg_RequiresVM", .serialized)
@MainActor
struct Cov3Cfg_RequiresVM {

    @Test("requiresVM returns true when vmRunning is true")
    func requiresVMWhenRunning() {
        let s = makeState()
        s.vmRunning = true
        #expect(s.requiresVM("test") == true)
    }

    @Test("requiresVM returns false when vmRunning is false")
    func requiresVMWhenNotRunning() {
        let s = makeState()
        s.vmRunning = false
        #expect(s.requiresVM("test") == false)
    }

    @Test("requiresVM sets errorMessage when VM not running")
    func requiresVMSetsError() {
        let s = makeState()
        s.vmRunning = false
        _ = s.requiresVM("Docker")
        #expect(s.errorMessage != nil)
        #expect(s.errorMessage?.contains("Docker") == true)
    }

    @Test("requiresVM shows toast when VM not running")
    func requiresVMShowsToast() {
        let s = makeState()
        s.vmRunning = false
        _ = s.requiresVM("SSH")
        #expect(s.isToastVisible == true)
    }
}

// ─── AppState.showError and showToast ────────────────────────────────────────

@Suite("Cov3Cfg_ShowErrorAndToast", .serialized)
@MainActor
struct Cov3Cfg_ShowErrorAndToast {

    @Test("showError sets errorMessage")
    func showErrorSetsMessage() {
        let s = makeState()
        s.showError("test error")
        #expect(s.errorMessage == "test error")
    }

    @Test("showError also shows toast")
    func showErrorShowsToast() {
        let s = makeState()
        s.showError("some failure")
        #expect(s.isToastVisible == true)
    }

    @Test("showToast sets toastMessage")
    func showToastSetsMessage() {
        let s = makeState()
        s.showToast("hello world")
        #expect(s.toastMessage == "hello world")
    }

    @Test("showToast sets isToastVisible to true")
    func showToastSetsVisible() {
        let s = makeState()
        s.showToast("ping")
        #expect(s.isToastVisible == true)
    }
}

// ─── AppState.requestConfirmation ────────────────────────────────────────────

@Suite("Cov3Cfg_RequestConfirmation", .serialized)
@MainActor
struct Cov3Cfg_RequestConfirmation {

    @Test("requestConfirmation stores message")
    func storesMessage() {
        let s = makeState()
        s.requestConfirmation("Delete this?") {}
        #expect(s.confirmationMessage == "Delete this?")
    }

    @Test("requestConfirmation sets showConfirmation to true")
    func setsShowConfirmation() {
        let s = makeState()
        s.requestConfirmation("Sure?") {}
        #expect(s.showConfirmation == true)
    }

    @Test("requestConfirmation action fires when invoked")
    func actionFires() {
        let s = makeState()
        var fired = false
        s.requestConfirmation("Proceed?") { fired = true }
        s.confirmationAction?()
        #expect(fired == true)
    }

    @Test("requestConfirmation action is nil before setting")
    func actionNilBeforeSetting() {
        let s = makeState()
        #expect(s.confirmationAction == nil)
    }
}

// ─── ColimaConfig.KubernetesConfig ───────────────────────────────────────────

@Suite("Cov3Cfg_KubernetesConfig", .serialized)
struct Cov3Cfg_KubernetesConfig {

    @Test("k3sArgs has default disable=traefik entry")
    func k3sArgsDefaultValue() {
        let c = ColimaConfig()
        #expect(c.kubernetes.k3sArgs == ["--disable=traefik"])
    }

    @Test("k3sArgs can hold multiple values")
    func k3sArgsMultipleValues() {
        var c = ColimaConfig()
        c.kubernetes.k3sArgs = ["--disable=traefik", "--flannel-backend=none"]
        #expect(c.kubernetes.k3sArgs.count == 2)
    }

    @Test("kubernetes port 0 means auto-assign")
    func k8sPortZero() {
        var c = ColimaConfig()
        c.kubernetes.port = 0
        #expect(c.kubernetes.port == 0)
    }

    @Test("kubernetes port can be set to specific value")
    func k8sPortSpecificValue() {
        var c = ColimaConfig()
        c.kubernetes.port = 6443
        #expect(c.kubernetes.port == 6443)
    }
}

// ─── MockContainer state values ──────────────────────────────────────────────

@Suite("Cov3Cfg_MockContainerStates", .serialized)
struct Cov3Cfg_MockContainerStates {

    @Test("running container state is 'running'")
    func runningState() {
        let c = MockContainer(id: "1", name: "web", image: "nginx", status: "Up", state: "running", ports: "", created: "1h")
        #expect(c.state == "running")
    }

    @Test("exited container state is 'exited'")
    func exitedState() {
        let c = MockContainer(id: "2", name: "db", image: "pg", status: "Exited", state: "exited", ports: "", created: "2h")
        #expect(c.state == "exited")
    }

    @Test("paused container state is 'paused'")
    func pausedState() {
        let c = MockContainer(id: "3", name: "cache", image: "redis", status: "Paused", state: "paused", ports: "", created: "3h")
        #expect(c.state == "paused")
    }

    @Test("MockContainer is Identifiable via id")
    func containerIdentifiable() {
        let c = MockContainer(id: "abc123", name: "myapp", image: "myimg", status: "Up", state: "running", ports: "", created: "now")
        #expect(c.id == "abc123")
    }
}
