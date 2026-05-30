import Foundation

/// Represents the colima.yaml configuration file.
/// Matches the schema from config/config.go in colima source.
struct ColimaConfig: Equatable {
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
                        default: break
                        }
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
        lines.append("docker: {}")
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
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static func parseKV(_ s: String) -> (String, String)? {
        guard let colonIdx = s.firstIndex(of: ":") else { return nil }
        let key = String(s[s.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
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
}
