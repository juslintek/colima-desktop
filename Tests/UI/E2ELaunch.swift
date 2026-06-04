import XCTest

/// Centralized launch configuration for E2E (XCUITest) suites.
///
/// E2E tests are end-to-end by default: they drive the **real** `ServiceProvider`
/// (request → DaemonClient/DockerClient → colima/docker → response). Set the
/// `E2E_BACKEND` environment variable to `mock` to run against `MockServiceProvider`
/// instead — required in environments that cannot run a real backend, such as the
/// Tart VM (no nested virtualization) or CI without Colima/Docker.
///
/// `--ui-testing` is always passed: it only enables UI-test affordances (window
/// visibility, always-visible hover actions) and does NOT select the backend.
enum E2ELaunch {
    static func configure(_ app: XCUIApplication) {
        let backend = ProcessInfo.processInfo.environment["E2E_BACKEND"]?.lowercased() ?? "real"
        app.launchArguments = ["--ui-testing", backend == "mock" ? "--backend-mock" : "--backend-real"]
    }
}
