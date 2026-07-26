import Foundation

/// Pure, dependency-free helpers backing the profile-scoped template
/// read/edit/save interface (`GetTemplate` / `SetTemplate`).
///
/// These are kept Sources-local and side-effect-free so the Property 18
/// (template read/save round-trip) test can exercise the exact serialization,
/// path, and validation logic used by the live `DaemonClient` without touching
/// the real `~/.colima` directory.
///
/// Path resolution mirrors the daemon's `profileShortName`
/// (`daemon/internal/server/config_server.go`): the default profile maps to
/// `~/.colima/_templates/default.yaml` — byte-identical to what the daemon and
/// the `colima` CLI read/write — while a named profile maps to a
/// profile-scoped override `~/.colima/_templates/<profile>.yaml`, so editing
/// one profile's template never clobbers the shared default that other newly
/// created VMs rely on.
enum ColimaTemplate {
    /// Directory that holds colima's VM templates, relative to the colima home.
    static let templatesDirName = "_templates"

    /// The canonical colima default template file name.
    static let defaultTemplateFileName = "default.yaml"

    /// User-facing note describing when template edits take effect. Templates
    /// are the base config for *newly created* VMs; existing VMs keep their own
    /// configuration until they are deleted and recreated.
    static let restartNote = """
    Template changes apply to newly created VMs only. Existing VMs keep their \
    current configuration until they are deleted and recreated. Editing the \
    template does not restart or modify a running VM.
    """

    /// Directory component for a profile's template, mirroring the daemon's
    /// `profileShortName`: "", "colima", and "default" all map to "default".
    static func shortName(for profile: String) -> String {
        switch profile {
        case "", "colima", "default": return "default"
        default: return profile
        }
    }

    /// Template file name for a profile (e.g. "default.yaml", "dev.yaml").
    static func fileName(for profile: String) -> String {
        "\(shortName(for: profile)).yaml"
    }

    /// Absolute path of a profile's template file under the given colima home
    /// (e.g. `~/.colima`). The default profile resolves to the canonical
    /// `<home>/_templates/default.yaml`.
    static func path(profile: String, colimaHome: String) -> String {
        (colimaHome as NSString)
            .appendingPathComponent(templatesDirName)
            + "/" + fileName(for: profile)
    }

    /// Absolute path of the shared default template under the given colima home.
    static func defaultPath(colimaHome: String) -> String {
        (colimaHome as NSString)
            .appendingPathComponent(templatesDirName)
            + "/" + defaultTemplateFileName
    }

    // MARK: - Serialization (SetTemplate / GetTemplate content)

    /// Serialize a template config to YAML for persistence (what `SetTemplate`
    /// writes to disk).
    static func encode(_ config: ColimaConfig) -> String {
        config.toYAML()
    }

    /// Parse template YAML back into a config (what `GetTemplate` returns).
    static func decode(_ yaml: String) -> ColimaConfig {
        ColimaConfig.fromYAML(yaml)
    }

    /// `SetTemplate` → `GetTemplate` round-trip on the config content, with no
    /// filesystem access. Anchors Property 18: saving a template and reading it
    /// back returns equivalent content.
    static func roundTrip(_ config: ColimaConfig) -> ColimaConfig {
        decode(encode(config))
    }

    // MARK: - Validation

    /// Known-valid VM types, container runtimes, and mount types accepted by
    /// colima. Used to give the user actionable validation feedback before a
    /// template is saved.
    static let validVMTypes: Set<String> = ["vz", "qemu", "krunkit"]
    static let validRuntimes: Set<String> = ["docker", "containerd", "incus"]
    static let validMountTypes: Set<String> = ["virtiofs", "9p", "sshfs"]

    /// Validate template YAML before saving. Returns an empty array when the
    /// content is acceptable, otherwise a list of human-readable issues.
    ///
    /// The checks are intentionally conservative: they reject content that
    /// colima would reject (empty, tab-indented, non-positive resources, or an
    /// unknown vmType/runtime/mountType) while leaving forward-compatible keys
    /// untouched.
    static func validationIssues(_ yaml: String) -> [String] {
        var issues: [String] = []

        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ["Template is empty. Provide valid colima YAML or reset to the current template."]
        }

        // YAML forbids tab characters for indentation.
        if yaml.contains("\t") {
            issues.append("YAML must not use tab characters for indentation; use spaces.")
        }

        let config = ColimaConfig.fromYAML(yaml)

        if config.cpu < 1 {
            issues.append("cpu must be at least 1.")
        }
        if config.memory < 1 {
            issues.append("memory (GiB) must be at least 1.")
        }
        if config.disk < 1 {
            issues.append("disk (GiB) must be at least 1.")
        }
        if !config.vmType.isEmpty, !validVMTypes.contains(config.vmType) {
            issues.append("vmType '\(config.vmType)' is not one of vz, qemu, krunkit.")
        }
        if !config.runtime.isEmpty, !validRuntimes.contains(config.runtime) {
            issues.append("runtime '\(config.runtime)' is not one of docker, containerd, incus.")
        }
        if !config.mountType.isEmpty, !validMountTypes.contains(config.mountType) {
            issues.append("mountType '\(config.mountType)' is not one of virtiofs, 9p, sshfs.")
        }

        return issues
    }

    /// Convenience: true when `validationIssues` is empty.
    static func isValid(_ yaml: String) -> Bool {
        validationIssues(yaml).isEmpty
    }
}
