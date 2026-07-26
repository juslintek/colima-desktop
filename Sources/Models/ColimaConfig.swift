import Foundation

/// Represents the colima.yaml configuration file.
/// Matches the schema from config/config.go in colima source.
struct ColimaConfig: Equatable {
    /// Original text is retained so saving through the form can preserve
    /// top-level keys introduced by newer Colima releases.
    var sourceYAML: String?
    var cpu: Int = 2
    var memory: Double = 2  // GiB, float32 in Go
    var disk: Int = 100
    var rootDisk: Int = 20
    var arch: String = "aarch64"
    var runtime: String = "docker"
    var modelRunner: String = "docker"
    var hostname: String = ""
    var vmType: String = "vz"
    var mountType: String = "virtiofs"
    var mountInotify: Bool = true
    var portForwarder: String = "ssh"
    var rosetta: Bool = false
    var binfmt: Bool = true
    var nestedVirtualization: Bool = false
    var autoActivate: Bool = true
    var forwardAgent: Bool = false
    var sshConfig: Bool = true
    var sshPort: Int = 0
    var cpuType: String = ""
    var diskImage: String = ""

    var kubernetes: Kubernetes = Kubernetes()
    var network: Network = Network()
    var docker: [String: Any] = [:]
    var mounts: [Mount] = []
    var provision: [Provision] = []
    var env: [String: String] = [:]

    struct Kubernetes: Equatable {
        var enabled: Bool = false
        var version: String = "v1.35.0+k3s1"
        var k3sArgs: [String] = ["--disable=traefik"]
        var port: Int = 0
    }

    struct Network: Equatable {
        var address: Bool = false
        var mode: String = "shared"
        var interface: String = "en0"
        var preferredRoute: Bool = false
        var dns: [String] = []
        var dnsHosts: [String: String] = [:]
        var hostAddresses: Bool = false
        var gatewayAddress: String = "192.168.5.2"
    }

    struct Mount: Equatable {
        var location: String
        var writable: Bool
    }

    struct Provision: Equatable {
        var mode: String  // system, user, after-boot, ready
        var script: String
    }

    static func == (lhs: ColimaConfig, rhs: ColimaConfig) -> Bool {
        lhs.cpu == rhs.cpu && lhs.memory == rhs.memory && lhs.disk == rhs.disk &&
        lhs.arch == rhs.arch && lhs.runtime == rhs.runtime && lhs.vmType == rhs.vmType
    }
}

// MARK: - YAML Parsing (simple key-value, handles colima.yaml structure)

extension ColimaConfig {
    /// Parse colima.yaml content into ColimaConfig
    static func fromYAML(_ yaml: String) -> ColimaConfig {
        var config = ColimaConfig()
        config.sourceYAML = yaml
        let lines = yaml.components(separatedBy: "\n")
        var i = 0
        var currentSection = ""
        var currentSubSection = ""

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }

            let indent = line.prefix(while: { $0 == " " }).count

            // Top-level keys (indent 0)
            if indent == 0 {
                currentSection = ""
                currentSubSection = ""
                if let (key, value) = parseKV(trimmed) {
                    switch key {
                    case "cpu": config.cpu = Int(value) ?? 2
                    case "memory": config.memory = Double(value) ?? 2
                    case "disk": config.disk = Int(value) ?? 100
                    case "rootDisk": config.rootDisk = Int(value) ?? 20
                    case "arch": config.arch = unquote(value)
                    case "runtime": config.runtime = unquote(value)
                    case "modelRunner": config.modelRunner = unquote(value)
                    case "hostname": config.hostname = unquote(value)
                    case "vmType": config.vmType = unquote(value)
                    case "mountType": config.mountType = unquote(value)
                    case "mountInotify": config.mountInotify = parseBool(value)
                    case "portForwarder": config.portForwarder = unquote(value)
                    case "rosetta": config.rosetta = parseBool(value)
                    case "binfmt": config.binfmt = parseBool(value)
                    case "nestedVirtualization": config.nestedVirtualization = parseBool(value)
                    case "autoActivate": config.autoActivate = parseBool(value)
                    case "forwardAgent": config.forwardAgent = parseBool(value)
                    case "sshConfig": config.sshConfig = parseBool(value)
                    case "sshPort": config.sshPort = Int(value) ?? 0
                    case "cpuType": config.cpuType = unquote(value)
                    case "diskImage": config.diskImage = unquote(value)
                    default: break
                    }
                } else if trimmed.hasSuffix(":") || trimmed.contains(": {}") || trimmed.contains(": []") || trimmed.contains(": null") {
                    currentSection = trimmed.components(separatedBy: ":").first ?? ""
                }
            }
            // Section content (indent 2+)
            else if indent >= 2 {
                if let (key, value) = parseKV(trimmed) {
                    switch currentSection {
                    case "kubernetes":
                        switch key {
                        case "enabled": config.kubernetes.enabled = parseBool(value)
                        case "version": config.kubernetes.version = unquote(value)
                        case "port": config.kubernetes.port = Int(value) ?? 0
                        default: break
                        }
                    case "network":
                        switch key {
                        case "address": config.network.address = parseBool(value)
                        case "mode": config.network.mode = unquote(value)
                        case "interface": config.network.interface = unquote(value)
                        case "preferredRoute": config.network.preferredRoute = parseBool(value)
                        case "hostAddresses": config.network.hostAddresses = parseBool(value)
                        case "gatewayAddress": config.network.gatewayAddress = unquote(value)
                        default:
                            if currentSubSection == "dnsHosts" {
                                config.network.dnsHosts[unquote(key)] = unquote(value)
                            }
                        }
                    case "docker": config.docker[unquote(key)] = parseYAMLValue(value)
                    case "env": config.env[unquote(key)] = unquote(value)
                    default: break
                    }
                } else if trimmed.hasPrefix("- ") {
                    let item = String(trimmed.dropFirst(2))
                    switch currentSection {
                    case "kubernetes" where currentSubSection == "k3sArgs":
                        config.kubernetes.k3sArgs.append(unquote(item))
                    case "network" where currentSubSection == "dns":
                        config.network.dns.append(unquote(item))
                    case "mounts":
                        // Parse mount entries: - location: ~/path
                        if let (mk, mv) = parseKV(item), mk == "location" {
                            let loc = unquote(mv)
                            // Look ahead for writable
                            var writable = true
                            if i + 1 < lines.count {
                                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                                if let (nk, nv) = parseKV(next), nk == "writable" {
                                    writable = parseBool(nv)
                                    i += 1
                                }
                            }
                            config.mounts.append(Mount(location: loc, writable: writable))
                        }
                    case "provision":
                        // Parse provision entries: - mode: system
                        if let (mk, mv) = parseKV(item), mk == "mode" {
                            let mode = unquote(mv)
                            var script = ""
                            // Look ahead for script
                            if i + 1 < lines.count {
                                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                                if next.hasPrefix("script:") {
                                    let scriptVal = next.dropFirst("script:".count).trimmingCharacters(in: .whitespaces)
                                    if scriptVal == "|" {
                                        // Multi-line script
                                        i += 2
                                        var scriptLines: [String] = []
                                        while i < lines.count {
                                            let sl = lines[i]
                                            let si = sl.prefix(while: { $0 == " " }).count
                                            if si >= 6 || sl.trimmingCharacters(in: .whitespaces).isEmpty {
                                                scriptLines.append(String(sl.dropFirst(min(6, sl.count))))
                                            } else { break }
                                            i += 1
                                        }
                                        script = scriptLines.joined(separator: "\n")
                                        i -= 1
                                    } else {
                                        script = unquote(scriptVal)
                                        i += 1
                                    }
                                }
                            }
                            config.provision.append(Provision(mode: mode, script: script))
                        }
                    default: break
                    }
                } else if trimmed.hasSuffix(":") {
                    currentSubSection = trimmed.replacingOccurrences(of: ":", with: "")
                    if currentSubSection == "k3sArgs" { config.kubernetes.k3sArgs = [] }
                }
            }
            i += 1
        }
        return config
    }

    /// Serialize ColimaConfig to YAML string
    func toYAML() -> String {
        var lines: [String] = []
        lines.append("cpu: \(cpu)")
        lines.append("disk: \(disk)")
        lines.append("memory: \(memory == floor(memory) ? "\(Int(memory))" : "\(memory)")")
        lines.append("arch: \(arch)")
        lines.append("runtime: \(runtime)")
        lines.append("modelRunner: \(modelRunner)")
        lines.append("hostname: \"\(hostname)\"")
        lines.append("")
        lines.append("kubernetes:")
        lines.append("  enabled: \(kubernetes.enabled)")
        lines.append("  version: \(kubernetes.version)")
        lines.append("  k3sArgs:")
        for arg in kubernetes.k3sArgs { lines.append("    - \(arg)") }
        lines.append("  port: \(kubernetes.port)")
        lines.append("")
        lines.append("autoActivate: \(autoActivate)")
        lines.append("")
        lines.append("network:")
        lines.append("  address: \(network.address)")
        lines.append("  mode: \(network.mode)")
        lines.append("  interface: \(network.interface)")
        lines.append("  preferredRoute: \(network.preferredRoute)")
        if network.dns.isEmpty {
            lines.append("  dns: null")
        } else {
            lines.append("  dns:")
            for d in network.dns { lines.append("    - \(d)") }
        }
        lines.append("  dnsHosts: \(network.dnsHosts.isEmpty ? "{}" : "")")
        if !network.dnsHosts.isEmpty {
            for (k, v) in network.dnsHosts { lines.append("    \(k): \(v)") }
        }
        lines.append("  hostAddresses: \(network.hostAddresses)")
        lines.append("  gatewayAddress: \(network.gatewayAddress)")
        lines.append("")
        lines.append("forwardAgent: \(forwardAgent)")
        if docker.isEmpty {
            lines.append("docker: {}")
        } else {
            lines.append("docker:")
            for key in docker.keys.sorted() {
                lines.append("  \(key): \(yamlScalar(docker[key]!))")
            }
        }
        lines.append("vmType: \(vmType)")
        lines.append("portForwarder: \(portForwarder)")
        lines.append("rosetta: \(rosetta)")
        lines.append("binfmt: \(binfmt)")
        lines.append("nestedVirtualization: \(nestedVirtualization)")
        lines.append("mountType: \(mountType)")
        lines.append("mountInotify: \(mountInotify)")
        lines.append("cpuType: \"\(cpuType)\"")
        if provision.isEmpty {
            lines.append("provision: null")
        } else {
            lines.append("provision:")
            for p in provision {
                lines.append("  - mode: \(p.mode)")
                if p.script.contains("\n") {
                    lines.append("    script: |")
                    for sl in p.script.components(separatedBy: "\n") { lines.append("      \(sl)") }
                } else {
                    lines.append("    script: \(p.script)")
                }
            }
        }
        lines.append("sshConfig: \(sshConfig)")
        lines.append("sshPort: \(sshPort)")
        if mounts.isEmpty {
            lines.append("mounts: []")
        } else {
            lines.append("mounts:")
            for m in mounts {
                lines.append("  - location: \(m.location)")
                lines.append("    writable: \(m.writable)")
            }
        }
        lines.append("diskImage: \"\(diskImage)\"")
        lines.append("rootDisk: \(rootDisk)")
        if env.isEmpty {
            lines.append("env: {}")
        } else {
            lines.append("env:")
            for (k, v) in env { lines.append("  \(k): \(v)") }
        }
        let canonical = lines.joined(separator: "\n") + "\n"
        guard let sourceYAML, !sourceYAML.isEmpty else { return canonical }
        return mergeTopLevelBlocks(original: sourceYAML, canonical: canonical)
    }

    // MARK: - Helpers

    private static func parseKV(_ s: String) -> (String, String)? {
        // Never interpret YAML list items (lines starting with "- ") as key-value pairs.
        // Without this guard, "- location: ~" would be parsed as key="- location", value="~",
        // silently bypassing the list-item handler and dropping all mount/provision/dns entries.
        guard !s.hasPrefix("- ") else { return nil }
        guard let colonIdx = s.firstIndex(of: ":") else { return nil }
        let key = String(s[s.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
        // Key must not be empty and must not contain spaces (which would indicate this isn't
        // a simple key: value pair but something else like a bare string with a colon).
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        let afterColon = s.index(after: colonIdx)
        guard afterColon < s.endIndex else { return nil }
        let value = String(s[afterColon...]).trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return nil }
        return (key, value)
    }

    private static func unquote(_ s: String) -> String {
        var v = s
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }

    private static func parseBool(_ s: String) -> Bool {
        s == "true" || s == "yes"
    }

    private static func parseYAMLValue(_ value: String) -> Any {
        let value = unquote(value)
        if value == "true" || value == "yes" { return true }
        if value == "false" || value == "no" { return false }
        if let int = Int(value) { return int }
        if let double = Double(value) { return double }
        return value
    }

    private func yamlScalar(_ value: Any) -> String {
        switch value {
        case let bool as Bool: return bool ? "true" : "false"
        case let int as Int: return "\(int)"
        case let double as Double: return "\(double)"
        case let string as String:
            if string.isEmpty || string.contains(":") || string.contains("#") || string.contains("\n") {
                let escaped = string.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            return string
        default: return "\"\(String(describing: value))\""
        }
    }

    /// Replace known top-level blocks while retaining unknown blocks verbatim.
    /// This keeps forward-compatible Colima options instead of silently
    /// deleting them when the form saves a configuration.
    private func mergeTopLevelBlocks(original: String, canonical: String) -> String {
        let known = Self.knownTopLevelKeys
        let canonicalBlocks = Self.topLevelBlocks(canonical)
        var emitted = Set<String>()
        var output: [String] = []
        for block in Self.topLevelBlocksInOrder(original) {
            guard let key = block.key else {
                output.append(contentsOf: block.lines)
                continue
            }
            if known.contains(key), let replacement = canonicalBlocks[key] {
                if !emitted.contains(key) {
                    output.append(contentsOf: mergeUnknownChildren(key: key, original: block.lines, canonical: replacement))
                }
                emitted.insert(key)
            } else {
                output.append(contentsOf: block.lines)
            }
        }
        for block in Self.topLevelBlocksInOrder(canonical) {
            if let key = block.key, known.contains(key), !emitted.contains(key) {
                output.append(contentsOf: block.lines)
                emitted.insert(key)
            }
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n") + "\n"
    }

    private func mergeUnknownChildren(key: String, original: [String], canonical: [String]) -> [String] {
        let recognized: Set<String>
        switch key {
        case "network":
            recognized = ["address", "mode", "interface", "preferredRoute", "dns", "dnsHosts", "hostAddresses", "gatewayAddress"]
        case "kubernetes":
            recognized = ["enabled", "version", "k3sArgs", "port"]
        case "docker": recognized = Set(docker.keys)
        case "env": recognized = Set(env.keys)
        default: return canonical
        }
        let extras = Self.childBlocks(original).filter { child in
            guard let childKey = child.key else { return false }
            return !recognized.contains(childKey)
        }.flatMap(\.lines)
        guard !extras.isEmpty else { return canonical }
        var merged = canonical
        while merged.last?.isEmpty == true { merged.removeLast() }
        merged.append(contentsOf: extras)
        merged.append("")
        return merged
    }

    private static func childBlocks(_ lines: [String]) -> [(key: String?, lines: [String])] {
        var result: [(String?, [String])] = []
        var key: String?
        var block: [String] = []
        func flush() {
            guard !block.isEmpty else { return }
            result.append((key, block))
            block = []
        }
        for line in lines.dropFirst() {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 2, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") {
                flush()
                key = String(trimmed[..<colon])
            }
            block.append(line)
        }
        flush()
        return result
    }

    private static func topLevelBlocks(_ yaml: String) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: topLevelBlocksInOrder(yaml).compactMap { block in
            block.key.map { ($0, block.lines) }
        })
    }

    private static func topLevelBlocksInOrder(_ yaml: String) -> [(key: String?, lines: [String])] {
        var blocks: [(String?, [String])] = []
        var currentKey: String?
        var currentLines: [String] = []
        func flush() {
            guard !currentLines.isEmpty else { return }
            blocks.append((currentKey, currentLines))
            currentLines = []
        }
        for line in yaml.components(separatedBy: "\n") {
            let isTopLevel = !line.isEmpty && !line.first!.isWhitespace && !line.hasPrefix("#")
            if isTopLevel, let colon = line.firstIndex(of: ":") {
                flush()
                currentKey = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            } else if isTopLevel {
                flush()
                currentKey = nil
            }
            currentLines.append(line)
        }
        flush()
        return blocks
    }
}

// MARK: - Round-trip safety, parse validation, and unknown-key preservation
//
// Task 7.4 (Requirement 7.4 / design Property 19): the macOS configuration UI
// loads from the REAL profile YAML and, on save, preserves every key present in
// the source that the UI does not model. The strategy here is to retain the
// original document text (`sourceYAML`) and re-emit known blocks while copying
// unrecognized top-level blocks (and unrecognized children of known sections)
// through verbatim — see `toYAML()` / `mergeTopLevelBlocks`. That keeps unknown
// mappings instead of decoding into a lossy fixed struct.
//
// The helpers below are pure and side-effect-free so the round-trip and
// unknown-key-preservation invariants can be exercised without touching the
// real `~/.colima` directory.

extension ColimaConfig {
    /// The top-level YAML keys the configuration model understands. Anything not
    /// in this set is an "unknown" key that must survive a load→edit→save cycle.
    /// Single source of truth reused by `mergeTopLevelBlocks` and the
    /// unknown-key helpers so the two can never drift apart.
    static let knownTopLevelKeys: Set<String> = [
        "cpu", "disk", "memory", "arch", "runtime", "modelRunner", "hostname",
        "kubernetes", "autoActivate", "network", "forwardAgent", "docker", "vmType",
        "portForwarder", "rosetta", "binfmt", "nestedVirtualization", "mountType",
        "mountInotify", "cpuType", "provision", "sshConfig", "sshPort", "mounts",
        "diskImage", "rootDisk", "env",
    ]

    /// Raised when configuration YAML cannot be parsed safely. Surfacing this
    /// (rather than silently producing a lossy config) is what lets callers
    /// avoid overwriting a config they failed to parse.
    enum ParseError: LocalizedError, Equatable {
        case malformed([String])

        var errorDescription: String? {
            switch self {
            case .malformed(let issues):
                return "Configuration YAML could not be parsed: \(issues.joined(separator: "; "))"
            }
        }
    }

    /// Structural problems that make YAML unsafe to parse. Intentionally
    /// conservative: it flags only content colima itself could never have
    /// written (YAML forbids tab characters for indentation), so a valid
    /// space-indented config with arbitrary unknown keys yields zero issues.
    static func structuralIssues(in yaml: String) -> [String] {
        var issues: [String] = []
        for (index, line) in yaml.components(separatedBy: "\n").enumerated() {
            // A tab anywhere in the leading whitespace is invalid YAML indentation.
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            if indentation.contains(where: { $0 == "\t" }) {
                issues.append("line \(index + 1): tab character used for indentation (YAML requires spaces)")
            }
        }
        return issues
    }

    /// Parse profile YAML, throwing `ParseError.malformed` when the document is
    /// structurally unsafe. On success the returned config retains `sourceYAML`
    /// so a later `toYAML()` preserves unknown keys.
    static func parse(_ yaml: String) throws -> ColimaConfig {
        let issues = structuralIssues(in: yaml)
        guard issues.isEmpty else { throw ParseError.malformed(issues) }
        return fromYAML(yaml)
    }

    /// The canonical load→save round-trip as a pure function: parse the YAML
    /// into the model, then serialize it back. Equivalent to what the
    /// configuration UI does across a load-then-save with no edits.
    static func roundTrip(_ yaml: String) -> String {
        fromYAML(yaml).toYAML()
    }

    /// All top-level keys declared in a YAML document, in declaration order.
    static func topLevelKeys(in yaml: String) -> [String] {
        topLevelBlocksInOrder(yaml).compactMap { $0.key }
    }

    /// Top-level keys the model does not understand — the ones a save must
    /// preserve verbatim.
    static func unknownTopLevelKeys(in yaml: String) -> [String] {
        topLevelKeys(in: yaml).filter { !knownTopLevelKeys.contains($0) }
    }

    /// True when serializing this config preserves every unknown top-level key
    /// that was present in `original`. Pure predicate for verifying Property 19.
    func preservesUnknownKeys(from original: String) -> Bool {
        let produced = Set(Self.topLevelKeys(in: toYAML()))
        return Self.unknownTopLevelKeys(in: original).allSatisfy(produced.contains)
    }
}

// Task 7.4 — configuration loads from the real profile YAML (DaemonClient.readConfig)
// and round-trips through toYAML()+mergeTopLevelBlocks so unknown keys are preserved.
