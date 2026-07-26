import Foundation
import SystemConfiguration

// MARK: - DependencyManager (CONTRACT Part C — macOS)
//
// Live dependency verification for the macOS frontend (Requirement 10 / roadmap
// R6.3). It reports the REAL host state — never a hardcoded `true` — for every
// tool Colima Desktop depends on, offers a concrete install path for anything
// missing, and reports cancellation, offline, and permission-denied conditions
// with actionable remediation.
//
// This mirrors the Linux peer (`linux/src/dependency_manager.rs`) and the
// CONTRACT Part C dependency set, extended with the macOS-only `krunkit`
// accelerator and with the installed/missing/outdated classification required by
// Requirement 10.1 (Property 20) and the install-path offer required by
// Requirement 10.2 (Property 21).
//
// Testability: every side effect is behind an injectable seam — a
// `DependencyProbe` (host detection) and a `DependencyInstaller` (the install
// action). The production seams do real work; tests inject fakes to drive any
// host state (Property 20 is universally quantified over "any host state").

/// One of the external tools the macOS frontend depends on.
public enum DependencyTool: String, CaseIterable, Identifiable, Sendable {
    case colima
    case lima
    case qemu
    case krunkit
    case dockerCLI = "docker-cli"
    case kubectl

    public var id: String { rawValue }

    /// Human-facing display name.
    public var displayName: String {
        switch self {
        case .colima: return "Colima"
        case .lima: return "Lima"
        case .qemu: return "QEMU"
        case .krunkit: return "krunkit"
        case .dockerCLI: return "Docker CLI"
        case .kubectl: return "kubectl"
        }
    }

    /// Executable name(s) probed on the host, most-specific first. `lima` ships
    /// its CLI as `limactl`; `qemu` differs by host architecture.
    public var binaryCandidates: [String] {
        switch self {
        case .colima: return ["colima"]
        case .lima: return ["limactl"]
        case .qemu: return ["qemu-system-aarch64", "qemu-system-x86_64", "qemu-img"]
        case .krunkit: return ["krunkit"]
        case .dockerCLI: return ["docker"]
        case .kubectl: return ["kubectl"]
        }
    }

    /// Homebrew formula used for the package-manager install path.
    public var brewFormula: String {
        switch self {
        case .colima: return "colima"
        case .lima: return "lima"
        case .qemu: return "qemu"
        case .krunkit: return "krunkit"
        case .dockerCLI: return "docker"
        case .kubectl: return "kubectl"
        }
    }

    /// Some formulae live in a tap; the install command must tap first.
    public var brewTap: String? {
        switch self {
        case .krunkit: return "slp/krunkit"
        default: return nil
        }
    }

    /// A signed direct-download landing page, used when Homebrew is unavailable
    /// (Requirement 10.2 — "a signed direct download"). These are the official,
    /// code-signed release pages for each tool.
    public var signedDownloadURL: String {
        switch self {
        case .colima: return "https://github.com/abiosoft/colima/releases/latest"
        case .lima: return "https://github.com/lima-vm/lima/releases/latest"
        case .qemu: return "https://www.qemu.org/download/#macos"
        case .krunkit: return "https://github.com/containers/krunkit/releases/latest"
        case .dockerCLI: return "https://download.docker.com/mac/static/stable/"
        case .kubectl: return "https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/"
        }
    }

    /// The lowest version considered current. A detected version below this is
    /// classified `outdated`. Compared against locally-bundled floors so the
    /// check never needs the network (offline-safe). `nil` means "any present
    /// version is acceptable".
    public var minimumVersion: String? {
        switch self {
        case .colima: return "0.6.0"
        case .lima: return "0.20.0"
        case .qemu: return "8.0.0"
        case .krunkit: return "0.1.0"
        case .dockerCLI: return "20.10.0"
        case .kubectl: return "1.24.0"
        }
    }

    /// Colima and the Docker CLI are hard requirements for the app to function;
    /// the rest are conditionally required (e.g. `qemu`/`krunkit` only for
    /// non-vz VMs, `kubectl` only when Kubernetes features are used).
    public var isRequired: Bool {
        switch self {
        case .colima, .dockerCLI: return true
        case .lima, .qemu, .krunkit, .kubectl: return false
        }
    }
}

/// The classification of a single tool on the host. Exactly one value is
/// assigned per tool (Requirement 10.1 / Property 20).
public enum DependencyState: String, Sendable {
    case installed
    case missing
    case outdated
}

/// How a missing or outdated tool can be installed/upgraded (Requirement 10.2 /
/// Property 21): either through the platform package manager, or a signed
/// direct download when no package manager is available.
public enum InstallPath: Equatable, Sendable {
    case packageManager(command: String)
    case signedDownload(url: String)

    /// A concise, user-facing description of the offered path.
    public var summary: String {
        switch self {
        case .packageManager(let command): return command
        case .signedDownload(let url): return "Signed download: \(url)"
        }
    }
}

/// The result of classifying one tool: its state, the observed version and
/// resolved path (when present), the offered install path (when not installed),
/// and an actionable remediation string.
public struct DependencyStatus: Identifiable, Equatable, Sendable {
    public let tool: DependencyTool
    public let state: DependencyState
    public let detectedVersion: String?
    public let resolvedPath: String?
    public let installPath: InstallPath?
    public let remediation: String

    public var id: String { tool.rawValue }

    public var isInstalled: Bool { state == .installed }
}

/// A raw host observation for one tool, produced by a `DependencyProbe`.
public struct ToolProbeResult: Equatable, Sendable {
    public var present: Bool
    public var resolvedPath: String?
    public var version: String?

    public init(present: Bool, resolvedPath: String? = nil, version: String? = nil) {
        self.present = present
        self.resolvedPath = resolvedPath
        self.version = version
    }

    public static let absent = ToolProbeResult(present: false)
}

// MARK: - Probe seam

/// The injectable detection seam. The production probe inspects the real host;
/// tests inject a fake to drive arbitrary host states.
public protocol DependencyProbe: Sendable {
    /// Observe a single tool's real presence + version on the host.
    func probe(_ tool: DependencyTool) -> ToolProbeResult
    /// Whether a package manager (Homebrew) is available for installs.
    func isPackageManagerAvailable() -> Bool
    /// Best-effort reachability check used to report the offline condition.
    func isOnline() -> Bool
}

/// The real host probe: resolves binaries in the known macOS install locations
/// and reads each tool's reported version by executing it.
public struct SystemDependencyProbe: DependencyProbe {
    /// Ordered search path: Apple-silicon Homebrew, Intel Homebrew, system.
    public static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    public init() {}

    public func probe(_ tool: DependencyTool) -> ToolProbeResult {
        guard let resolved = Self.resolve(tool.binaryCandidates) else {
            return .absent
        }
        let version = Self.readVersion(binaryPath: resolved, tool: tool)
        return ToolProbeResult(present: true, resolvedPath: resolved, version: version)
    }

    public func isPackageManagerAvailable() -> Bool {
        Self.resolve(["brew"]) != nil
    }

    public func isOnline() -> Bool {
        Self.hostIsReachable("github.com")
    }

    // MARK: Detection helpers

    /// First candidate binary that exists in a known search path, else `nil`.
    static func resolve(_ candidates: [String]) -> String? {
        for candidate in candidates {
            if candidate.contains("/") {
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
                continue
            }
            for dir in searchPaths {
                let full = "\(dir)/\(candidate)"
                if FileManager.default.isExecutableFile(atPath: full) { return full }
            }
        }
        return nil
    }

    /// Run the tool's version command and extract a semantic version. Never
    /// throws: a tool that cannot report a version is treated as "present,
    /// version unknown".
    static func readVersion(binaryPath: String, tool: DependencyTool) -> String? {
        let args: [String]
        switch tool {
        case .kubectl: args = ["version", "--client", "--output=yaml"]
        case .colima: args = ["version"]        // colima has a `version` subcommand
        case .lima: args = ["--version"]        // limactl uses the --version flag
        default: args = ["--version"]
        }
        guard let output = runCapturing(binaryPath, args) else { return nil }
        return DependencyVersion.extract(from: output)
    }

    /// Execute a command and capture combined stdout+stderr, or `nil` on
    /// failure to launch. Bounded so a hung binary cannot wedge the check.
    static func runCapturing(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":") + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// SystemConfiguration reachability — a lightweight, non-blocking proxy for
    /// "is the host online". Used only to report the offline condition; it never
    /// blocks a dependency check.
    static func hostIsReachable(_ host: String) -> Bool {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else { return false }
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else { return false }
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        return isReachable && !needsConnection
    }
}

// MARK: - Installer seam

/// The injectable install seam. The production installer shells out to the
/// package manager; tests inject a fake to exercise cancel / offline /
/// permission-denied outcomes deterministically.
public protocol DependencyInstaller: Sendable {
    func run(_ path: InstallPath) async throws
}

/// Typed failures an installer can surface so the manager can map them to a
/// user-facing outcome with remediation.
public enum DependencyInstallError: Error, Equatable, Sendable {
    case offline
    case permissionDenied
    case cancelled
    case failed(String)
}

/// The real installer: runs the package-manager command. A signed-download path
/// cannot be automated safely, so it surfaces guidance instead of silently
/// doing nothing.
public struct SystemDependencyInstaller: DependencyInstaller {
    public init() {}

    public func run(_ path: InstallPath) async throws {
        switch path {
        case .signedDownload(let url):
            throw DependencyInstallError.failed(
                "No package manager available. Download and install a signed build from \(url), then re-check."
            )
        case .packageManager(let command):
            try Self.runShell(command)
        }
    }

    /// Execute a `brew ...` command. Maps a non-zero exit that looks like a
    /// permissions problem onto `.permissionDenied` so the caller can render
    /// remediation rather than a raw error.
    static func runShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw DependencyInstallError.failed("Failed to launch installer: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = (String(data: data, encoding: .utf8) ?? "").lowercased()
        if process.terminationStatus != 0 {
            if output.contains("permission denied") || output.contains("not permitted") || output.contains("must be run as root") {
                throw DependencyInstallError.permissionDenied
            }
            throw DependencyInstallError.failed(output.isEmpty ? "Installer exited \(process.terminationStatus)" : output)
        }
    }
}

// MARK: - Install outcome

/// The result of an install attempt (Requirements 10.3 / 10.4 / 10.5).
public enum InstallOutcome: Equatable, Sendable {
    case installed
    case cancelled(String)
    case offline(String)
    case permissionDenied(String)
    case failed(String)
}

// MARK: - DependencyManager

/// Classifies and (optionally) installs the tracked dependencies. Immutable
/// apart from its injected probe, so it is safe to share across concurrency
/// domains.
public final class DependencyManager: @unchecked Sendable {
    private let probe: DependencyProbe

    public init(probe: DependencyProbe = SystemDependencyProbe()) {
        self.probe = probe
    }

    /// Classify every tracked tool. Guarantees exactly one `DependencyStatus`
    /// per tool with exactly one `DependencyState` (Property 20).
    public func checkAll() -> [DependencyStatus] {
        DependencyTool.allCases.map(classify)
    }

    /// Classify a single tool against the real host state.
    public func classify(_ tool: DependencyTool) -> DependencyStatus {
        let observation = probe.probe(tool)
        let state = Self.state(for: tool, observation: observation)
        let installPath: InstallPath? = state == .installed ? nil : offeredInstallPath(for: tool)
        let remediation = Self.remediation(tool: tool, state: state, installPath: installPath, version: observation.version)
        return DependencyStatus(
            tool: tool,
            state: state,
            detectedVersion: observation.version,
            resolvedPath: observation.resolvedPath,
            installPath: installPath,
            remediation: remediation
        )
    }

    /// Pure classification: absent → missing; present-and-below-floor →
    /// outdated; otherwise installed. Total over every observation, so exactly
    /// one state is always produced.
    static func state(for tool: DependencyTool, observation: ToolProbeResult) -> DependencyState {
        guard observation.present else { return .missing }
        if let floor = tool.minimumVersion,
           let detected = observation.version,
           DependencyVersion.isOlder(detected, than: floor) {
            return .outdated
        }
        return .installed
    }

    /// The install path offered for a missing/outdated tool (Property 21):
    /// Homebrew when available, otherwise a signed direct download. Always
    /// returns a concrete path — a missing tool is never left without one.
    public func offeredInstallPath(for tool: DependencyTool) -> InstallPath {
        guard probe.isPackageManagerAvailable() else {
            return .signedDownload(url: tool.signedDownloadURL)
        }
        if let tap = tool.brewTap {
            return .packageManager(command: "brew tap \(tap) && brew install \(tool.brewFormula)")
        }
        return .packageManager(command: "brew install \(tool.brewFormula)")
    }

    /// Attempt to install/upgrade a tool, translating the injected installer's
    /// typed failures into user-facing outcomes.
    ///
    /// - Cancellation before any work returns a *safe* state (Requirement 10.3).
    /// - Being offline is reported rather than attempting a doomed download
    ///   (Requirement 10.4).
    /// - A permission failure is reported with remediation (Requirement 10.5).
    public func install(
        _ tool: DependencyTool,
        using installer: DependencyInstaller = SystemDependencyInstaller(),
        isCancelled: @Sendable () -> Bool = { false }
    ) async -> InstallOutcome {
        // Honor a cancellation requested before any side effect: nothing was
        // started, so the host is already in a safe state.
        if isCancelled() {
            return .cancelled("Installation of \(tool.displayName) was cancelled before it started. No changes were made.")
        }
        guard probe.isOnline() else {
            return .offline("Cannot install \(tool.displayName) while offline. Reconnect to the internet and try again.")
        }
        let path = offeredInstallPath(for: tool)
        do {
            try await installer.run(path)
            if isCancelled() {
                return .cancelled("Installation of \(tool.displayName) was cancelled. Re-check dependencies to see the current state.")
            }
            // Re-observe to confirm the install actually took effect.
            return classify(tool).isInstalled
                ? .installed
                : .failed("\(tool.displayName) still not detected after install. Ensure \(path.summary) completed, then re-check.")
        } catch DependencyInstallError.cancelled {
            return .cancelled("Installation of \(tool.displayName) was cancelled. No further changes will be made.")
        } catch DependencyInstallError.offline {
            return .offline("Lost network connectivity while installing \(tool.displayName). Reconnect and try again.")
        } catch DependencyInstallError.permissionDenied {
            return .permissionDenied(
                "Installing \(tool.displayName) was denied permission. Grant administrator access (or run \(path.summary) from a terminal), then re-check."
            )
        } catch DependencyInstallError.failed(let message) {
            return .failed(message)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// A live backend check: does the Docker daemon actually respond over the
    /// given profile-scoped socket? This is stronger than binary presence — it
    /// proves the daemon is up and answering (`GET /_ping`). Returns `false`
    /// when the socket is absent or unresponsive rather than throwing.
    public func dockerDaemonResponds(socketPath: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        let client = DockerClient(socketPath: socketPath)
        return (try? await client.ping()) == true
    }

    // MARK: Remediation copy

    static func remediation(tool: DependencyTool, state: DependencyState, installPath: InstallPath?, version: String?) -> String {
        switch state {
        case .installed:
            let v = version.map { " (\($0))" } ?? ""
            return "\(tool.displayName)\(v) is installed and current."
        case .missing:
            let path = installPath?.summary ?? "install it, then re-check"
            let scope = tool.isRequired ? "Required." : "Optional."
            return "\(scope) \(tool.displayName) is not installed. Install it: \(path)"
        case .outdated:
            let detected = version.map { "found \($0)" } ?? "older version found"
            let floor = tool.minimumVersion.map { ", need \($0)+" } ?? ""
            let path = installPath?.summary ?? "upgrade it, then re-check"
            return "\(tool.displayName) is outdated (\(detected)\(floor)). Upgrade: \(path)"
        }
    }
}

// MARK: - Version comparison

/// Minimal semantic-version handling for dependency classification. Tolerates
/// the varied version strings tools emit ("colima version 0.10.1", "Docker
/// version 29.5.2, build ...", "Client Version: v1.29.0", ...).
public enum DependencyVersion {
    /// Extract the first dotted numeric version from arbitrary tool output.
    public static func extract(from text: String) -> String? {
        guard let range = text.range(of: #"[0-9]+\.[0-9]+(\.[0-9]+)?"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    /// Compare two dotted versions numerically, component by component. Missing
    /// components are treated as 0 (so "1.2" == "1.2.0").
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = components(lhs)
        let r = components(rhs)
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    /// True when `version` is strictly older than `floor`.
    public static func isOlder(_ version: String, than floor: String) -> Bool {
        compare(version, floor) == .orderedAscending
    }

    private static func components(_ version: String) -> [Int] {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return cleaned.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
