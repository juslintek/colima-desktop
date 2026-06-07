import Testing
import Foundation
@testable import ColimaDesktop

/// Deterministic failure-mode tests for DockerClient that need NO real backend:
/// they point the client at a bogus socket and assert the error path, plus verify
/// DockerError message formatting. Always run (no opt-in required).
@Suite("DockerClient Error Paths")
struct DockerClientErrorTests {

    private func bogusClient() -> DockerClient {
        DockerClient(socketPath: "/tmp/colima-desktop-e2e-nonexistent-\(UUID().uuidString).sock")
    }

    @Test("listContainers against a missing socket throws socketNotFound")
    func missingSocketThrows() async {
        let client = bogusClient()
        do {
            _ = try await client.listContainers()
            Issue.record("Expected socketNotFound for a nonexistent socket")
        } catch let error as DockerError {
            if case .socketNotFound = error { } else {
                Issue.record("Expected .socketNotFound, got \(error)")
            }
        } catch {
            Issue.record("Expected DockerError, got \(error)")
        }
    }

    @Test("ping against a missing socket throws (not a silent false)")
    func pingMissingSocketThrows() async {
        let client = bogusClient()
        do {
            _ = try await client.ping()
            Issue.record("Expected ping to throw on a missing socket")
        } catch { /* expected */ }
    }

    @Test("DockerError descriptions are human-readable and include context")
    func errorDescriptions() {
        #expect(DockerError.invalidResponse.errorDescription?.isEmpty == false)
        let api = DockerError.apiError(404, "no such container").errorDescription ?? ""
        #expect(api.contains("404"))
        #expect(api.contains("no such container"))
        let sock = DockerError.socketNotFound("/tmp/x.sock").errorDescription ?? ""
        #expect(sock.contains("/tmp/x.sock"))
    }

    @Test("profile-based init resolves the colima socket path for the profile")
    func profileSocketResolution() async {
        // A made-up profile has no socket → operations must throw socketNotFound,
        // proving the per-profile path resolution + guard works without a real VM.
        let client = DockerClient(profile: "colima-desktop-e2e-not-a-real-profile")
        do {
            _ = try await client.listImages()
            Issue.record("Expected socketNotFound for a profile with no socket")
        } catch let error as DockerError {
            if case .socketNotFound = error { } else {
                Issue.record("Expected .socketNotFound, got \(error)")
            }
        } catch {
            Issue.record("Expected DockerError, got \(error)")
        }
    }
}
