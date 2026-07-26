import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - Property 13 — Destructive-action confirmation gate (macOS)
//
// Feature: cross-platform-live-verification, Property 13
//
// Design Property 13 (Validates: Requirements 4.4, 5.5, 6.6, 7.2):
//   "For any destructive action on any frontend, no RPC is invoked unless an
//    explicit confirmation has been given; denying or dismissing the
//    confirmation issues no RPC."
//
// This file is the macOS slice (Requirement 7.2). Task 7.2 made the nine
// destructive Docker mutation gates headless-testable via `AppState`: each
// destructive action ARMS a pending confirmation (sets `showConfirmation`,
// `confirmationAction`, `confirmationMessage`) and issues NO service call until
// `confirmPendingAction()` runs the stored action; `cancelPendingConfirmation()`
// clears the pending confirmation WITHOUT invoking it.
//
// The nine destructive Docker mutations under test:
//   container:  remove · kill · prune
//   image:      remove · prune
//   volume:     remove · prune
//   network:    remove · prune
//
// Approach: a recording `ServiceProvider` (composition over `MockServiceProvider`)
// counts every service call plus a per-destructive-RPC counter. For any mutation,
// the test asserts:
//   • arming issues ZERO service calls but raises a pending confirmation,
//   • denying/cancelling issues ZERO service calls,
//   • only `confirmPendingAction()` issues exactly the one mapped RPC.
//
// No modal (NSAlert / NSSavePanel / NSOpenPanel / runModal) is ever invoked, and
// no live backend is used — the whole gate is assertable through observable
// `@Published` state, so this runs headless/CI-safe.

extension Tag {
    /// Per-property unique tag so sibling property-test files (Properties 17/18/19/…)
    /// never collide on a shared identifier. The canonical tag string
    /// "Feature: cross-platform-live-verification, Property 13" is also carried in
    /// every suite/test display name below.
    @Tag static var property13DestructiveConfirmation: Self
}

@MainActor
@Suite(
    "Property 13 — destructive-action confirmation gate [Feature: cross-platform-live-verification, Property 13]",
    .serialized,
    .tags(.property13DestructiveConfirmation)
)
struct DestructiveConfirmationPropertyTests {

    /// Randomized iterations for the combined property. Comfortably exceeds the
    /// required minimum of 100.
    static let iterations = 200
    /// Randomized iterations for the denial-sequence property.
    static let sequenceIterations = 150

    // MARK: - Property 13.a — canonical: arm → (confirm | deny) invariant

    @Test("armed destructive Docker mutation issues no RPC until confirmed; denial issues none — Feature: cross-platform-live-verification, Property 13")
    func destructiveConfirmationGate() async {
        let mutations = DestructiveMutation.allCases
        for i in 0..<Self.iterations {
            let seed = 0x1300_0000_0000_0001 &+ UInt64(i)
            var rng = SplitMix64(seed: seed)
            let mutation = mutations[Int.random(in: 0..<mutations.count, using: &rng)]
            let resource = P13Gen.resourceName(&rng)
            let recorder = CallRecorder()
            let st = makeState(recorder)

            // (1) Arming raises a pending confirmation and issues NO service call.
            mutation.arm(on: st, resource: resource)
            #expect(st.showConfirmation,
                    "arm did not raise showConfirmation — \(mutation.label) iter=\(i) seed=\(seed)")
            #expect(st.confirmationAction != nil,
                    "arm did not store a pending action — \(mutation.label) iter=\(i) seed=\(seed)")
            #expect(!st.confirmationMessage.isEmpty,
                    "arm produced an empty confirmation message — \(mutation.label) iter=\(i) seed=\(seed)")
            #expect(recorder.totalCalls == 0,
                    "arming issued \(recorder.totalCalls) service call(s) before any confirmation — \(mutation.label) iter=\(i) seed=\(seed)")

            if Bool.random(using: &rng) {
                // (2a) Confirm ⇒ exactly the mapped RPC is issued, only now.
                st.confirmPendingAction()
                let n = await awaitCount(recorder, key: mutation.serviceKey, atLeast: 1)
                #expect(n == 1,
                        "confirm issued mapped RPC '\(mutation.serviceKey)' \(n) time(s), expected exactly 1 — \(mutation.label) iter=\(i) seed=\(seed)")
                // No OTHER destructive RPC may fire — the gate dispatches exactly one.
                for other in DestructiveMutation.allServiceKeys where other != mutation.serviceKey {
                    #expect(recorder.count(other) == 0,
                            "confirming \(mutation.label) also issued destructive RPC '\(other)' — iter=\(i) seed=\(seed)")
                }
                #expect(!st.showConfirmation,
                        "confirm left showConfirmation raised — \(mutation.label) iter=\(i) seed=\(seed)")
                #expect(st.confirmationAction == nil,
                        "confirm left a pending action armed — \(mutation.label) iter=\(i) seed=\(seed)")
            } else {
                // (2b) Deny/cancel ⇒ ZERO service calls of any kind.
                st.cancelPendingConfirmation()
                await settle()
                #expect(recorder.totalCalls == 0,
                        "denying the confirmation issued \(recorder.totalCalls) service call(s) — \(mutation.label) iter=\(i) seed=\(seed)")
                #expect(!st.showConfirmation,
                        "cancel left showConfirmation raised — \(mutation.label) iter=\(i) seed=\(seed)")
                #expect(st.confirmationAction == nil,
                        "cancel left a pending action armed — \(mutation.label) iter=\(i) seed=\(seed)")
            }
        }
    }

    // MARK: - Property 13.b — confirm sweep: every gate maps to exactly its RPC

    @Test("each destructive gate issues exactly its mapped RPC only after confirmPendingAction — Feature: cross-platform-live-verification, Property 13")
    func confirmSweepIssuesExactlyMappedRPC() async {
        for mutation in DestructiveMutation.allCases {
            let recorder = CallRecorder()
            let st = makeState(recorder)

            mutation.arm(on: st, resource: "e2e-\(mutation.serviceKey)")
            #expect(recorder.totalCalls == 0,
                    "arming \(mutation.label) issued a service call before confirmation")

            st.confirmPendingAction()
            let n = await awaitCount(recorder, key: mutation.serviceKey, atLeast: 1)
            #expect(n == 1,
                    "\(mutation.label): expected mapped RPC '\(mutation.serviceKey)' exactly once, got \(n)")
            for other in DestructiveMutation.allServiceKeys where other != mutation.serviceKey {
                #expect(recorder.count(other) == 0,
                        "\(mutation.label) also issued destructive RPC '\(other)'")
            }
        }
    }

    // MARK: - Property 13.c — deny sweep: every gate issues nothing on cancel

    @Test("each destructive gate issues ZERO RPCs when the confirmation is cancelled — Feature: cross-platform-live-verification, Property 13")
    func denySweepIssuesNoRPC() async {
        for mutation in DestructiveMutation.allCases {
            let recorder = CallRecorder()
            let st = makeState(recorder)

            mutation.arm(on: st, resource: "e2e-\(mutation.serviceKey)")
            #expect(st.showConfirmation, "\(mutation.label): arm did not raise a confirmation")

            st.cancelPendingConfirmation()
            await settle()
            #expect(recorder.totalCalls == 0,
                    "\(mutation.label): cancelling issued \(recorder.totalCalls) service call(s), expected 0")
            #expect(recorder.count(mutation.serviceKey) == 0,
                    "\(mutation.label): mapped RPC fired despite cancellation")
        }
    }

    // MARK: - Property 13.d — randomized denial sequences never issue an RPC

    @Test("arming then denying destructive mutations across randomized sequences never issues an RPC — Feature: cross-platform-live-verification, Property 13")
    func randomizedDenialSequencesIssueNoRPC() async {
        let mutations = DestructiveMutation.allCases
        for i in 0..<Self.sequenceIterations {
            let seed = 0x1300_DE00_0000_0001 &+ UInt64(i)
            var rng = SplitMix64(seed: seed)
            let recorder = CallRecorder()
            let st = makeState(recorder)

            let steps = Int.random(in: 1...6, using: &rng)
            for _ in 0..<steps {
                let mutation = mutations[Int.random(in: 0..<mutations.count, using: &rng)]
                mutation.arm(on: st, resource: P13Gen.resourceName(&rng))
                #expect(st.showConfirmation,
                        "arm did not raise a confirmation mid-sequence — iter=\(i) seed=\(seed)")
                // Randomly deny now, or re-arm (overwriting the pending action) before
                // an eventual cancel. Either way, no action is ever invoked.
                if Bool.random(using: &rng) {
                    st.cancelPendingConfirmation()
                    #expect(!st.showConfirmation,
                            "cancel left showConfirmation raised mid-sequence — iter=\(i) seed=\(seed)")
                }
            }
            // Clear anything still armed at the end of the sequence.
            st.cancelPendingConfirmation()
            await settle()
            #expect(recorder.totalCalls == 0,
                    "denial-only sequence issued \(recorder.totalCalls) service call(s) — iter=\(i) seed=\(seed) steps=\(steps)")
        }
    }

    // MARK: - Helpers

    /// Fresh `AppState` wired to a recording provider, with the VM marked running
    /// so the destructive mutations pass their `requiresVM(...)` guard (otherwise a
    /// confirmed action would bail out before ever reaching the service — which would
    /// mask the "confirm issues the RPC" half of the property).
    private func makeState(_ recorder: CallRecorder) -> AppState {
        let st = AppState(services: RecordingServiceProvider(recorder))
        st.vmRunning = true
        return st
    }

    /// Poll until the recorder observes at least `target` calls of `key`, or the
    /// timeout elapses. The confirmed mutation issues its RPC inside a
    /// `Task { @MainActor in … }`, so we must yield/sleep to let it run.
    private func awaitCount(
        _ recorder: CallRecorder,
        key: String,
        atLeast target: Int,
        timeout: TimeInterval = 2.0
    ) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if recorder.count(key) >= target { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 3_000_000) // 3ms
        }
        return recorder.count(key)
    }

    /// Give any (erroneously) spawned work a chance to run, so a "no call"
    /// assertion is robust rather than merely observing a not-yet-started task.
    private func settle(_ times: Int = 8) async {
        for _ in 0..<times {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }
    }
}

// MARK: - The nine destructive Docker mutations

/// Enumerates every destructive Docker mutation gated behind a confirmation in
/// `AppState`, along with the arming call and the exact recorded service-call key
/// the confirmed action must ultimately issue.
private enum DestructiveMutation: CaseIterable {
    case removeContainer, killContainer, pruneContainers
    case removeImage, pruneImages
    case removeVolume, pruneVolumes
    case removeNetwork, pruneNetworks

    /// The recorder key of the single `ServiceProvider` RPC this gate must issue
    /// on confirmation (and never before).
    var serviceKey: String {
        switch self {
        case .removeContainer: return "removeContainer"
        case .killContainer:   return "killContainer"
        case .pruneContainers: return "pruneContainers"
        case .removeImage:     return "removeImage"
        case .pruneImages:     return "pruneImages"
        case .removeVolume:    return "removeVolume"
        case .pruneVolumes:    return "pruneVolumes"
        case .removeNetwork:   return "removeNetwork"
        case .pruneNetworks:   return "pruneNetworks"
        }
    }

    var label: String {
        switch self {
        case .removeContainer: return "container remove"
        case .killContainer:   return "container kill"
        case .pruneContainers: return "container prune"
        case .removeImage:     return "image remove"
        case .pruneImages:     return "image prune"
        case .removeVolume:    return "volume remove"
        case .pruneVolumes:    return "volume prune"
        case .removeNetwork:   return "network remove"
        case .pruneNetworks:   return "network prune"
        }
    }

    /// The set of all nine destructive service keys — used to assert that a
    /// confirmed gate issues exactly its own RPC and no other destructive one.
    static let allServiceKeys: Set<String> = Set(DestructiveMutation.allCases.map(\.serviceKey))

    /// Arm the confirmation for this mutation. This must issue NO service call —
    /// it only stores the pending action + message and raises `showConfirmation`.
    @MainActor
    func arm(on state: AppState, resource: String) {
        switch self {
        case .removeContainer: state.confirmRemoveContainer(name: resource)
        case .killContainer:   state.confirmKillContainer(name: resource)
        case .pruneContainers: state.confirmPruneContainers()
        case .removeImage:     state.confirmRemoveImage(id: resource)
        case .pruneImages:     state.confirmPruneImages()
        case .removeVolume:    state.confirmRemoveVolume(name: resource)
        case .pruneVolumes:    state.confirmPruneVolumes()
        case .removeNetwork:   state.confirmRemoveNetwork(name: resource)
        case .pruneNetworks:   state.confirmPruneNetworks()
        }
    }
}

// MARK: - Thread-safe call recorder

/// Counts every `ServiceProvider` call plus per-method tallies. Lock-protected
/// because the confirmed mutation's RPC executes off the main actor (a
/// nonisolated `async` provider method), while the test reads counts on the main
/// actor.
private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var total = 0

    func record(_ method: String) {
        lock.lock()
        counts[method, default: 0] += 1
        total += 1
        lock.unlock()
    }

    func count(_ method: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[method, default: 0]
    }

    var totalCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return total
    }
}

// MARK: - Recording ServiceProvider (records every call, forwards to a real mock)

/// A `ServiceProvider` that records every call before delegating to an inner
/// `MockServiceProvider` (so return shapes stay valid for `AppState`'s refresh
/// parsing). Intentionally NOT a `MockServiceProvider` subclass: `AppState.init`
/// only auto-sets `vmRunning` for `MockServiceProvider`, and the test sets
/// `vmRunning` explicitly, so the recording type stays fully in control.
private final class RecordingServiceProvider: ServiceProvider {
    let recorder: CallRecorder
    private let inner = MockServiceProvider()

    init(_ recorder: CallRecorder) { self.recorder = recorder }

    // VM
    func startVM(profile: String) async throws { recorder.record("startVM"); try await inner.startVM(profile: profile) }
    func stopVM(profile: String, force: Bool) async throws { recorder.record("stopVM"); try await inner.stopVM(profile: profile, force: force) }
    func restartVM(profile: String) async throws { recorder.record("restartVM"); try await inner.restartVM(profile: profile) }
    func deleteVM(profile: String, data: Bool) async throws { recorder.record("deleteVM"); try await inner.deleteVM(profile: profile, data: data) }
    func vmStatus(profile: String) async throws -> VMStatusInfo { recorder.record("vmStatus"); return try await inner.vmStatus(profile: profile) }
    func vmVersion() async throws -> String { recorder.record("vmVersion"); return try await inner.vmVersion() }
    func updateVM(profile: String) async throws { recorder.record("updateVM"); try await inner.updateVM(profile: profile) }
    func pruneVM(profile: String, all: Bool) async throws { recorder.record("pruneVM"); try await inner.pruneVM(profile: profile, all: all) }
    func sshConfig(profile: String) async throws -> String { recorder.record("sshConfig"); return try await inner.sshConfig(profile: profile) }

    // Profiles
    func listProfiles() async throws -> [ProfileListItem] { recorder.record("listProfiles"); return try await inner.listProfiles() }
    func createProfile(name: String, config: ColimaStartConfig) async throws { recorder.record("createProfile"); try await inner.createProfile(name: name, config: config) }
    func deleteProfile(name: String, data: Bool) async throws { recorder.record("deleteProfile"); try await inner.deleteProfile(name: name, data: data) }
    func cloneProfile(source: String, dest: String) async throws { recorder.record("cloneProfile"); try await inner.cloneProfile(source: source, dest: dest) }

    // Machines
    func listMachines() async throws -> [[String: Any]] { recorder.record("listMachines"); return try await inner.listMachines() }

    // Kubernetes
    func k8sStart(profile: String) async throws { recorder.record("k8sStart"); try await inner.k8sStart(profile: profile) }
    func k8sStop(profile: String) async throws { recorder.record("k8sStop"); try await inner.k8sStop(profile: profile) }
    func k8sReset(profile: String) async throws { recorder.record("k8sReset"); try await inner.k8sReset(profile: profile) }
    func kubectlExec(_ command: String, profile: String) async throws -> String { recorder.record("kubectlExec"); return try await inner.kubectlExec(command, profile: profile) }

    // Containers
    func listContainers() async throws -> [[String: Any]] { recorder.record("listContainers"); return try await inner.listContainers() }
    func startContainer(id: String) async throws { recorder.record("startContainer"); try await inner.startContainer(id: id) }
    func stopContainer(id: String) async throws { recorder.record("stopContainer"); try await inner.stopContainer(id: id) }
    func killContainer(id: String) async throws { recorder.record("killContainer"); try await inner.killContainer(id: id) }
    func restartContainer(id: String) async throws { recorder.record("restartContainer"); try await inner.restartContainer(id: id) }
    func pauseContainer(id: String) async throws { recorder.record("pauseContainer"); try await inner.pauseContainer(id: id) }
    func unpauseContainer(id: String) async throws { recorder.record("unpauseContainer"); try await inner.unpauseContainer(id: id) }
    func removeContainer(id: String) async throws { recorder.record("removeContainer"); try await inner.removeContainer(id: id) }
    func createContainer(name: String, image: String) async throws -> String { recorder.record("createContainer"); return try await inner.createContainer(name: name, image: image) }
    func createContainer(name: String, image: String, options: ContainerCreateOptions) async throws -> String { recorder.record("createContainerOptions"); return try await inner.createContainer(name: name, image: image, options: options) }
    func renameContainer(id: String, newName: String) async throws { recorder.record("renameContainer"); try await inner.renameContainer(id: id, newName: newName) }
    func containerLogs(id: String) async throws -> String { recorder.record("containerLogs"); return try await inner.containerLogs(id: id) }
    func inspectContainer(id: String) async throws -> String { recorder.record("inspectContainer"); return try await inner.inspectContainer(id: id) }
    func containerTop(id: String) async throws -> String { recorder.record("containerTop"); return try await inner.containerTop(id: id) }
    func containerStats(id: String) async throws -> String { recorder.record("containerStats"); return try await inner.containerStats(id: id) }
    func containerChanges(id: String) async throws -> String { recorder.record("containerChanges"); return try await inner.containerChanges(id: id) }
    func pruneContainers() async throws { recorder.record("pruneContainers"); try await inner.pruneContainers() }

    // Images
    func listImages() async throws -> [[String: Any]] { recorder.record("listImages"); return try await inner.listImages() }
    func pullImage(name: String) async throws { recorder.record("pullImage"); try await inner.pullImage(name: name) }
    func removeImage(id: String) async throws { recorder.record("removeImage"); try await inner.removeImage(id: id) }
    func inspectImage(name: String) async throws -> String { recorder.record("inspectImage"); return try await inner.inspectImage(name: name) }
    func imageHistory(name: String) async throws -> String { recorder.record("imageHistory"); return try await inner.imageHistory(name: name) }
    func tagImage(name: String, repo: String, tag: String) async throws { recorder.record("tagImage"); try await inner.tagImage(name: name, repo: repo, tag: tag) }
    func pushImage(name: String) async throws { recorder.record("pushImage"); try await inner.pushImage(name: name) }
    func searchImages(term: String) async throws -> [[String: Any]] { recorder.record("searchImages"); return try await inner.searchImages(term: term) }
    func pruneImages() async throws { recorder.record("pruneImages"); try await inner.pruneImages() }

    // Volumes
    func listVolumes() async throws -> [[String: Any]] { recorder.record("listVolumes"); return try await inner.listVolumes() }
    func createVolume(name: String) async throws { recorder.record("createVolume"); try await inner.createVolume(name: name) }
    func removeVolume(name: String) async throws { recorder.record("removeVolume"); try await inner.removeVolume(name: name) }
    func inspectVolume(name: String) async throws -> String { recorder.record("inspectVolume"); return try await inner.inspectVolume(name: name) }
    func pruneVolumes() async throws { recorder.record("pruneVolumes"); try await inner.pruneVolumes() }

    // Networks
    func listNetworks() async throws -> [[String: Any]] { recorder.record("listNetworks"); return try await inner.listNetworks() }
    func createNetwork(name: String) async throws { recorder.record("createNetwork"); try await inner.createNetwork(name: name) }
    func removeNetwork(name: String) async throws { recorder.record("removeNetwork"); try await inner.removeNetwork(name: name) }
    func inspectNetwork(id: String) async throws -> String { recorder.record("inspectNetwork"); return try await inner.inspectNetwork(id: id) }
    func connectNetwork(networkId: String, containerId: String) async throws { recorder.record("connectNetwork"); try await inner.connectNetwork(networkId: networkId, containerId: containerId) }
    func disconnectNetwork(networkId: String, containerId: String) async throws { recorder.record("disconnectNetwork"); try await inner.disconnectNetwork(networkId: networkId, containerId: containerId) }
    func pruneNetworks() async throws { recorder.record("pruneNetworks"); try await inner.pruneNetworks() }

    // Monitoring
    func processList(profile: String) async throws -> String { recorder.record("processList"); return try await inner.processList(profile: profile) }
    func killProcess(profile: String, pid: Int) async throws { recorder.record("killProcess"); try await inner.killProcess(profile: profile, pid: pid) }

    // Streaming
    func streamEvents(handler: @escaping (DockerEvent) -> Void) -> Task<Void, Never>? { recorder.record("streamEvents"); return inner.streamEvents(handler: handler) }
    func streamLogs(containerId: String, handler: @escaping (String) -> Void) -> Task<Void, Never>? { recorder.record("streamLogs"); return inner.streamLogs(containerId: containerId, handler: handler) }
    func streamStats(containerId: String, handler: @escaping (ContainerStats) -> Void) -> Task<Void, Never>? { recorder.record("streamStats"); return inner.streamStats(containerId: containerId, handler: handler) }

    // Profile switching
    func switchProfile(name: String) async throws { recorder.record("switchProfile"); try await inner.switchProfile(name: name) }

    // Configuration
    func readConfig(profile: String) async throws -> ColimaConfig { recorder.record("readConfig"); return try await inner.readConfig(profile: profile) }
    func writeConfig(profile: String, config: ColimaConfig) async throws { recorder.record("writeConfig"); try await inner.writeConfig(profile: profile, config: config) }

    // Template
    func getTemplate(profile: String) async throws -> ColimaConfig { recorder.record("getTemplate"); return try await inner.getTemplate(profile: profile) }
    func setTemplate(profile: String, config: ColimaConfig) async throws { recorder.record("setTemplate"); try await inner.setTemplate(profile: profile, config: config) }

    // Command execution
    func executeCommand(tool: String, args: [String], profile: String?) async throws -> String { recorder.record("executeCommand"); return try await inner.executeCommand(tool: tool, args: args, profile: profile) }

    // AI Models
    func modelList(runner: String, profile: String) async throws -> [AIModelInfo] { recorder.record("modelList"); return try await inner.modelList(runner: runner, profile: profile) }
    func modelPull(name: String, runner: String, profile: String) async throws { recorder.record("modelPull"); try await inner.modelPull(name: name, runner: runner, profile: profile) }
    func modelRun(name: String, runner: String, profile: String) async throws { recorder.record("modelRun"); try await inner.modelRun(name: name, runner: runner, profile: profile) }
    func modelServe(name: String?, runner: String, port: Int?, profile: String) async throws { recorder.record("modelServe"); try await inner.modelServe(name: name, runner: runner, port: port, profile: profile) }
    func modelStop(name: String, profile: String) async throws { recorder.record("modelStop"); try await inner.modelStop(name: name, profile: profile) }

    // Installation
    func isColimaInstalled() async -> Bool { recorder.record("isColimaInstalled"); return await inner.isColimaInstalled() }
    func installColima() async throws { recorder.record("installColima"); try await inner.installColima() }
}

// MARK: - Randomized resource-name generator

private enum P13Gen {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// A non-empty, safety-prefixed resource name (used where the gate takes one;
    /// prune gates ignore it). Widens the input space across iterations.
    static func resourceName(_ rng: inout SplitMix64) -> String {
        let len = Int.random(in: 3...12, using: &rng)
        var s = "e2e-"
        for _ in 0..<len { s.append(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]) }
        return s
    }
}

// MARK: - Seeded RNG (reproducible counterexamples)

/// Deterministic SplitMix64 PRNG so every failing iteration is reproducible from
/// the seed printed in its failure message.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
