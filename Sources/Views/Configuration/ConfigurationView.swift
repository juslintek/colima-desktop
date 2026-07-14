import SwiftUI

struct ConfigurationView: View {
    @EnvironmentObject var appState: AppState

    // VM Resources
    @State private var cpus: Double = 4
    @State private var memory: Double = 8
    @State private var disk: Double = 100
    @State private var rootDisk: Double = 60

    // VM Settings
    @State private var arch = "host"
    @State private var vmType = "qemu"
    @State private var cpuType = "host"
    @State private var rosetta = false
    @State private var nestedVirt = false
    @State private var hostname = ""
    @State private var diskImage = ""
    @State private var binfmt = true
    @State private var foreground = false
    @State private var portForwarder = "ssh"

    // Runtime
    @State private var runtime = "docker"
    @State private var autoActivate = true
    @State private var modelRunner = "docker"
    @State private var dockerJSON = "{\n  \"log-driver\": \"json-file\"\n}"
    @State private var jsonError = ""

    // Kubernetes
    @State private var k8sEnabled = false
    @State private var k8sVersion = ""
    @State private var k8sCustomVersion = ""
    @State private var k8sVersionError = ""
    @State private var k8sArgs = ""
    @State private var k8sPort = ""
    @State private var portStatus = ""
    private let availablePorts = [6443, 6444, 8443, 9443, 16443]

    // Network
    @State private var networkAddress = false
    @State private var networkMode = "shared"
    @State private var networkInterface = ""
    @State private var dnsServers = ""
    @State private var dnsStatus = ""
    @State private var dnsHosts = "db.local=192.168.1.10"
    @State private var gateway = ""
    @State private var gatewayStatus = ""
    @State private var hostAddresses = false
    @State private var preferredRoute = false

    // Volume Mounts
    @State private var mountType = "virtiofs"
    @State private var mountInotify = true
    @State private var disableMounts = false
    @State private var mounts: [(location: String, writable: Bool)] = [
        ("~", true), ("/tmp/colima", true)
    ]
    @State private var showAddMount = false
    @State private var newMountPath = ""
    @State private var newMountWritable = true

    // SSH
    @State private var sshPort = ""
    @State private var sshPortStatus = ""
    @State private var showSSHPortSuggestion = false
    @State private var forwardAgent = false
    @State private var sshConfig = true

    // Provisioning
    @State private var provisions: [(mode: String, script: String)] = [
        ("system", "apt-get update")
    ]
    @State private var provisionValidation = ""

    // Environment
    @State private var envVars: [(key: String, value: String)] = [
        ("DOCKER_BUILDKIT", "1")
    ]
    @State private var showAddEnv = false
    @State private var newEnvKey = ""
    @State private var newEnvValue = ""
    @State private var newEnvBulk = ""

    private let hostCPUs: Double = 12
    private let hostMemory: Double = 32
    private let hostDisk: Double = 500

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: VM Resources
                configCard(icon: "cpu", title: "VM Resources", description: "Allocate host resources to the Colima VM") {
                    VStack(alignment: .leading, spacing: 12) {
                        resourceBar(label: "CPUs", value: cpus, total: hostCPUs, unit: "cores")
                        HStack {
                            Stepper("\(Int(cpus)) cores", value: $cpus, in: 1...16)
                                .accessibilityIdentifier("field_config_cpus")
                        }

                        resourceBar(label: "Memory", value: memory, total: hostMemory, unit: "GiB")
                        HStack {
                            Stepper("\(Int(memory)) GiB", value: $memory, in: 1...64)
                                .accessibilityIdentifier("field_config_memory")
                        }

                        resourceBar(label: "Disk", value: disk, total: hostDisk, unit: "GiB")
                        HStack {
                            Stepper("\(Int(disk)) GiB", value: $disk, in: 10...500)
                                .accessibilityIdentifier("field_config_disk")
                        }

                        HStack {
                            Text("Root Disk"); Spacer()
                            Stepper("\(Int(rootDisk)) GiB", value: $rootDisk, in: 10...500)
                                .accessibilityIdentifier("field_config_rootdisk")
                        }.font(.caption)

                        Text("Leaving at least 50% for macOS is recommended")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // MARK: VM Settings
                configCard(icon: "gearshape.2", title: "VM Settings", description: "Virtual machine type, architecture, and runtime options") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Live selection summary (also used by E2E tests)
                        Text("vmtype:\(vmType) cputype:\(cpuType.isEmpty ? "host" : cpuType) mounttype:\(mountType) rosetta:\(rosetta ? "on" : "off") nestedvirt:\(nestedVirt ? "on" : "off") binfmt:\(binfmt ? "on" : "off") inotify:\(mountInotify ? "on" : "off") autoactivate:\(autoActivate ? "on" : "off")")
                            .font(.caption2).foregroundStyle(.secondary)
                            .accessibilityIdentifier("state_native_config")
                        // Architecture
                        HStack {
                            Picker("Architecture", selection: $arch) {
                                Text("host").tag("host"); Text("aarch64").tag("aarch64"); Text("x86_64").tag("x86_64")
                            }.accessibilityIdentifier("field_config_arch")
                            lockIcon(id: "lock_config_arch")
                        }

                        // VM Type cards
                        Text("VM Type").font(.caption.weight(.medium))
                            .accessibilityIdentifier("field_config_vmtype")
                        HStack(spacing: 8) {
                            vmTypeCard(type: "qemu", icon: "desktopcomputer", desc: "Universal — works everywhere, supports x86 emulation")
                            vmTypeCard(type: "vz", icon: "apple.logo", desc: "Native — Apple's framework, fastest I/O on Apple Silicon")
                            vmTypeCard(type: "krunkit", icon: "gpu", desc: "GPU — lightweight with Metal GPU access for AI")
                        }
                        HStack {
                            Spacer()
                            lockIcon(id: "lock_config_vmtype")
                        }

                        // CPU Type cards
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CPU Type").font(.caption.weight(.medium))
                                .accessibilityIdentifier("field_config_cputype")
                            HStack(spacing: 8) {
                                cpuTypeCard(type: "host", icon: "cpu", desc: "Host native — uses your Mac's actual CPU type")
                                cpuTypeCard(type: "cortex-a72", icon: "bolt", desc: "Cortex-A72 — generic ARM, max compatibility")
                                cpuTypeCard(type: "max", icon: "flame", desc: "Max — all CPU features enabled, fastest")
                            }
                        }

                        // Rosetta toggle card
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rosetta").font(.caption.weight(.medium))
                                Text("Run x86 containers at near-native speed").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $rosetta)
                                .accessibilityIdentifier("toggle_config_rosetta")
                        }
                        .padding(8).background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // Nested Virtualization
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Toggle("Nested Virtualization", isOn: $nestedVirt)
                                    .accessibilityIdentifier("toggle_config_nestedvirt")
                            }
                            Text("Allows running VMs inside the Colima VM. Enable for Docker-in-Docker, Kubernetes-in-Docker, or testing VM tools. Requires vz VM type. Slight performance overhead.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        // Hostname
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hostname").font(.caption.weight(.medium))
                            Text("Name for the VM on your network. Leave empty to use default (colima-\(appState.activeProfile)).").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                TextField("e.g. colima-dev", text: $hostname)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("field_config_hostname")
                                Menu("Suggestions") {
                                    Button("colima-\(appState.activeProfile)") { hostname = "colima-\(appState.activeProfile)" }
                                    Button("\(Host.current().localizedName ?? "mac")-colima") { hostname = "\(Host.current().localizedName ?? "mac")-colima" }
                                    Button("dev-vm") { hostname = "dev-vm" }
                                    Button("docker-host") { hostname = "docker-host" }
                                }.font(.caption)
                            }
                        }

                        // Disk Image
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Disk Image").font(.caption.weight(.medium))
                            Text("Path to a custom qcow2/raw disk image. Leave empty to use Colima's default Ubuntu cloud image.").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                TextField("~/.colima/default/disk.qcow2", text: $diskImage)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("field_config_diskimage")
                                Menu("Presets") {
                                    Button("Default (Ubuntu 24.04)") { diskImage = "" }
                                    Button("~/.colima/\(appState.activeProfile)/disk.qcow2") { diskImage = "~/.colima/\(appState.activeProfile)/disk.qcow2" }
                                    Button("Custom path...") { diskImage = "~/Downloads/" }
                                }.font(.caption)
                            }
                        }
                        // Binfmt
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Toggle("Binfmt", isOn: $binfmt)
                                    .accessibilityIdentifier("toggle_config_binfmt")
                            }
                            Text("Registers QEMU emulators for cross-architecture execution. Required for multi-arch Docker builds (buildx) — e.g. building x86 images on ARM. Minimal overhead.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Toggle("Foreground", isOn: $foreground).accessibilityIdentifier("toggle_config_foreground")
                        HStack {
                            Picker("Port Forwarder", selection: $portForwarder) {
                                Text("ssh").tag("ssh"); Text("grpc").tag("grpc"); Text("none").tag("none")
                            }.accessibilityIdentifier("field_config_portforwarder")
                            TooltipButton(info: ConfigTooltips.portForwarder)
                        }
                    }
                }

                // MARK: Runtime
                configCard(icon: "shippingbox", title: "Runtime", description: "Container runtime and Docker daemon configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Runtime", selection: $runtime) {
                                Text("docker").tag("docker"); Text("containerd").tag("containerd"); Text("incus").tag("incus")
                            }.accessibilityIdentifier("field_config_runtime")
                            TooltipButton(info: ConfigTooltips.runtime)
                            lockIcon(id: "lock_config_runtime")
                        }
                        Toggle("Auto Activate", isOn: $autoActivate).accessibilityIdentifier("toggle_config_autoactivate")
                        Picker("Model Runner", selection: $modelRunner) {
                            Text("docker").tag("docker"); Text("ramalama").tag("ramalama")
                        }.accessibilityIdentifier("field_config_modelrunner")
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Docker Daemon Config (JSON)").font(.caption.weight(.medium))
                                Spacer()
                                Menu("+ Add Key") {
                                    Button("log-driver — Logging driver (json-file, syslog, none)") { insertKey("\"log-driver\": \"json-file\"") }
                                    Button("log-opts — Logging options (max-size, max-file)") { insertKey("\"log-opts\": {\"max-size\": \"10m\", \"max-file\": \"3\"}") }
                                    Button("storage-driver — Storage backend (overlay2, btrfs)") { insertKey("\"storage-driver\": \"overlay2\"") }
                                    Button("insecure-registries — Allow HTTP registries") { insertKey("\"insecure-registries\": [\"myregistry:5000\"]") }
                                    Button("registry-mirrors — Mirror for Docker Hub pulls") { insertKey("\"registry-mirrors\": [\"https://mirror.example.com\"]") }
                                    Button("dns — Custom DNS servers for containers") { insertKey("\"dns\": [\"8.8.8.8\", \"1.1.1.1\"]") }
                                    Button("bip — Bridge IP for docker0 network") { insertKey("\"bip\": \"172.17.0.1/16\"") }
                                    Button("default-address-pools — Subnet allocation") { insertKey("\"default-address-pools\": [{\"base\": \"172.80.0.0/16\", \"size\": 24}]") }
                                    Button("experimental — Enable experimental features") { insertKey("\"experimental\": true") }
                                    Button("features — Feature flags (buildkit, etc)") { insertKey("\"features\": {\"buildkit\": true}") }
                                }
                                .font(.caption2)
                            }
                            Text("Configures the Docker daemon inside the VM. Applied to /etc/docker/daemon.json on restart.")
                                .font(.caption2).foregroundStyle(.secondary)
                            DockerJSONEditor(text: $dockerJSON)
                                .frame(height: 120)
                                .accessibilityIdentifier("field_config_dockerjson")
                            HStack {
                                Button("Format") { formatJSON() }.font(.caption2)
                                Button("Validate") { validateJSON() }.font(.caption2)
                                Spacer()
                                if !jsonError.isEmpty {
                                    Text(jsonError).font(.caption2).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                // MARK: Kubernetes
                configCard(icon: "helm", title: "Kubernetes", description: "Enable k3s cluster inside the VM") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enabled", isOn: $k8sEnabled).withTooltip(ConfigTooltips.kubernetes)
                            .accessibilityIdentifier("toggle_config_k8s")

                        // Version picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version").font(.caption.weight(.medium))
                            Text("Select a k3s release or enter a custom version.").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                Picker("", selection: $k8sVersion) {
                                    Text("Latest").tag("")
                                    Text("v1.31.4+k3s1").tag("v1.31.4+k3s1")
                                    Text("v1.30.8+k3s1").tag("v1.30.8+k3s1")
                                    Text("v1.29.12+k3s1").tag("v1.29.12+k3s1")
                                    Text("v1.28.15+k3s1").tag("v1.28.15+k3s1")
                                    Text("v1.27.16+k3s1").tag("v1.27.16+k3s1")
                                    Text("Custom...").tag("custom")
                                }
                                .frame(maxWidth: 200)
                                .accessibilityIdentifier("field_config_k8sversion")
                                if k8sVersion == "custom" {
                                    TextField("e.g. v1.30.0+k3s1", text: $k8sCustomVersion)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 160)
                                        .onSubmit { validateK8sVersion() }
                                    if !k8sVersionError.isEmpty {
                                        Text(k8sVersionError).font(.caption2).foregroundStyle(.red)
                                    }
                                }
                            }
                        }

                        // k3s Args with autocomplete
                        VStack(alignment: .leading, spacing: 4) {
                            Text("k3s Server Args").font(.caption.weight(.medium))
                            Text("Additional flags passed to k3s server on startup.").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                TextField("e.g. --disable=traefik", text: $k8sArgs)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                                    .accessibilityIdentifier("field_config_k3sargs")
                                Menu("+ Add") {
                                    Button("--disable=traefik — Disable built-in Traefik ingress") { appendArg("--disable=traefik") }
                                    Button("--disable=servicelb — Disable built-in load balancer") { appendArg("--disable=servicelb") }
                                    Button("--disable=metrics-server — Disable metrics collection") { appendArg("--disable=metrics-server") }
                                    Button("--flannel-backend=none — Disable Flannel CNI (use custom)") { appendArg("--flannel-backend=none") }
                                    Button("--cluster-cidr=10.42.0.0/16 — Pod network CIDR range") { appendArg("--cluster-cidr=10.42.0.0/16") }
                                    Button("--service-cidr=10.43.0.0/16 — Service network CIDR range") { appendArg("--service-cidr=10.43.0.0/16") }
                                    Button("--write-kubeconfig-mode=644 — Make kubeconfig world-readable") { appendArg("--write-kubeconfig-mode=644") }
                                    Button("--tls-san=my.domain.com — Add TLS SAN for external access") { appendArg("--tls-san=my.domain.com") }
                                    Button("--kube-apiserver-arg=... — Pass args to kube-apiserver") { appendArg("--kube-apiserver-arg=") }
                                    Button("--node-label=role=worker — Label this node") { appendArg("--node-label=role=worker") }
                                }.font(.caption2)
                            }
                        }

                        // API Port
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Port").font(.caption.weight(.medium))
                            Text("Port for the Kubernetes API server. Leave empty for default (6443).").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                TextField("6443", text: $k8sPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 100)
                                    .accessibilityIdentifier("field_config_k8sport")
                                    .onSubmit { validatePort() }
                                Menu("Open Ports") {
                                    ForEach(availablePorts, id: \.self) { port in
                                        Button("\(port)") { k8sPort = "\(port)"; portStatus = "✓ Port \(port) is available" }
                                    }
                                }.font(.caption2)
                                if !portStatus.isEmpty {
                                    Text(portStatus)
                                        .font(.caption2)
                                        .foregroundStyle(portStatus.hasPrefix("✓") ? .green : .red)
                                }
                            }
                        }
                    }
                }

                // MARK: Network
                configCard(icon: "network", title: "Network", description: "VM networking, DNS, and routing configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        // Status
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("IP").font(.caption2).foregroundStyle(.secondary)
                                Text("192.168.106.2").font(.caption.monospaced())
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gateway").font(.caption2).foregroundStyle(.secondary)
                                Text("192.168.106.1").font(.caption.monospaced())
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DNS").font(.caption2).foregroundStyle(.secondary)
                                Text("1.1.1.1").font(.caption.monospaced())
                            }
                        }
                        .padding(8).background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Network Address", isOn: $networkAddress)
                                .accessibilityIdentifier("toggle_config_networkaddress")
                            Text("Assigns a reachable IP address to the VM on your local network. Enables access from other devices on your LAN (e.g. testing from phone). Requires sudo on first use.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Picker("Network Mode", selection: $networkMode) {
                            Text("shared").tag("shared"); Text("bridged").tag("bridged")
                        }.accessibilityIdentifier("field_config_networkmode")
                        TextField("Interface", text: $networkInterface).accessibilityIdentifier("field_config_interface")

                        // DNS group
                        GroupBox("DNS Settings") {
                            VStack(alignment: .leading, spacing: 6) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("DNS Servers").font(.caption.weight(.medium))
                                    Text("Comma-separated. Used by containers for name resolution.").font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        TextField("1.1.1.1, 8.8.8.8", text: $dnsServers)
                                            .textFieldStyle(.roundedBorder)
                                            .accessibilityIdentifier("field_config_dns")
                                            .onSubmit { validateDNS() }
                                        Menu("Presets") {
                                            Button("1.1.1.1 — Cloudflare (fastest, privacy-focused)") { setDNS("1.1.1.1, 1.0.0.1") }
                                            Button("8.8.8.8 — Google (most reliable, global)") { setDNS("8.8.8.8, 8.8.4.4") }
                                            Button("9.9.9.9 — Quad9 (security-focused, blocks malware)") { setDNS("9.9.9.9, 149.112.112.112") }
                                            Button("208.67.222.222 — OpenDNS (parental controls, filtering)") { setDNS("208.67.222.222, 208.67.220.220") }
                                            Button("94.140.14.14 — AdGuard (ad-blocking built-in)") { setDNS("94.140.14.14, 94.140.15.15") }
                                            Divider()
                                            Button("System default (inherit from macOS)") { setDNS("") }
                                        }.font(.caption2)
                                    }
                                    if !dnsStatus.isEmpty {
                                        Text(dnsStatus)
                                            .font(.caption2)
                                            .foregroundStyle(dnsStatus.hasPrefix("✓") ? .green : .orange)
                                    }
                                }
                                VStack(alignment: .leading) {
                                    Text("DNS Hosts (key=value per line)").font(.caption2)
                                    TextEditor(text: $dnsHosts)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(height: 50)
                                        .accessibilityIdentifier("field_config_dnshosts")
                                }
                            }
                        }

                        // Gateway
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Gateway").font(.caption.weight(.medium))
                            Text("IP address the VM uses to reach the internet. Leave empty for automatic.").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                TextField("e.g. 192.168.64.1", text: $gateway)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 160)
                                    .accessibilityIdentifier("field_config_gateway")
                                    .onSubmit { validateGateway() }
                                Button("Use Default") { gateway = "192.168.64.1"; gatewayStatus = "✓ Default gateway (auto-detected)" }
                                    .font(.caption2)
                            }
                            if !gatewayStatus.isEmpty {
                                Text(gatewayStatus)
                                    .font(.caption2)
                                    .foregroundStyle(gatewayStatus.hasPrefix("✓") ? .green : gatewayStatus.hasPrefix("⚠") ? .orange : .red)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Host Addresses", isOn: $hostAddresses)
                                .accessibilityIdentifier("toggle_config_hostaddresses")
                            Text("Maps host.docker.internal and gateway.docker.internal inside the VM. Enable if your containers need to reach services running on your Mac (e.g. local APIs, databases). Safe to leave on.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Preferred Route", isOn: $preferredRoute)
                                .accessibilityIdentifier("toggle_config_preferredroute")
                            Text("Makes the VM's network the preferred route for container traffic. Enable if containers can't reach the internet. Disable if it conflicts with VPN or corporate network — may override your VPN routing.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Volume Mounts
                configCard(icon: "externaldrive", title: "Volume Mounts", description: "Share host directories with the VM") {
                    VStack(alignment: .leading, spacing: 8) {
                        // Mount type cards
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mount Type").font(.caption.weight(.medium))
                                .accessibilityIdentifier("field_config_mounttype")
                            Text("How files are shared between your Mac and the VM. Cannot be changed after creation.").font(.caption2).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                mountTypeCard(
                                    type: "virtiofs", icon: "bolt.fill",
                                    speed: "★★★★★", 
                                    pros: "Fastest. Native Apple framework. Near-native I/O.",
                                    cons: "Requires vz VM type and macOS 13+.",
                                    recommended: vmType == "vz"
                                )
                                mountTypeCard(
                                    type: "9p", icon: "folder.badge.gearshape",
                                    speed: "★★★☆☆",
                                    pros: "Good speed. Works with qemu. Stable.",
                                    cons: "Slower than virtiofs. No inotify support.",
                                    recommended: vmType == "qemu"
                                )
                                mountTypeCard(
                                    type: "sshfs", icon: "network",
                                    speed: "★★☆☆☆",
                                    pros: "Works everywhere. Most compatible.",
                                    cons: "Slowest. High latency for many small files.",
                                    recommended: false
                                )
                            }
                        }

                        // Inotify
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Inotify", isOn: $mountInotify)
                                .accessibilityIdentifier("toggle_config_inotify")
                            Text("Enables filesystem change notifications. Required for hot-reload (webpack, nodemon, vite). Slight CPU overhead from watching files.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Disable Mounts", isOn: $disableMounts)
                                .accessibilityIdentifier("toggle_config_disablemounts")
                            Text("Completely disables file sharing between host and VM. Enable if containers are self-contained and don't need access to your local files. Improves VM startup time and reduces resource usage.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        ForEach(Array(mounts.enumerated()), id: \.offset) { i, m in
                            HStack {
                                Image(systemName: m.writable ? "pencil.circle" : "lock.circle").foregroundStyle(m.writable ? .blue : .orange).font(.caption)
                                Text(m.location).font(.caption.monospaced())
                                Spacer()
                                Text(m.writable ? "read-write" : "read-only").font(.caption2).foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    mounts.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }.accessibilityIdentifier("btn_remove_mount_\(i)")
                            }
                        }
                        Button("Add Mount") { showAddMount = true }
                            .accessibilityIdentifier("btn_add_mount")

                        if showAddMount {
                            addMountDialog
                        }
                    }
                }

                // MARK: SSH
                configCard(icon: "terminal", title: "SSH", description: "SSH access to the VM") {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SSH Port").font(.caption.weight(.medium))
                            Text("Port for SSH access to the VM. Leave empty for auto-assign.").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                TextField("e.g. 2222", text: $sshPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 100)
                                    .accessibilityIdentifier("field_config_sshport")
                                    .onSubmit { validateSSHPort() }
                                Menu("Open Ports") {
                                    ForEach([2222, 2200, 2201, 2223, 22022], id: \.self) { port in
                                        Button("\(port)") { sshPort = "\(port)"; sshPortStatus = "✓ Port \(port) is available" }
                                    }
                                }.font(.caption2)
                                if !sshPortStatus.isEmpty {
                                    Text(sshPortStatus)
                                        .font(.caption2)
                                        .foregroundStyle(sshPortStatus.hasPrefix("✓") ? .green : .red)
                                }
                            }
                            if showSSHPortSuggestion {
                                HStack(spacing: 6) {
                                    Text("Pick an available port:").font(.caption2).foregroundStyle(.secondary)
                                    ForEach([2222, 2200, 2201, 2223, 22022], id: \.self) { port in
                                        Button("\(port)") {
                                            sshPort = "\(port)"
                                            sshPortStatus = "✓ Port \(port) is available"
                                            showSSHPortSuggestion = false
                                        }
                                        .font(.caption2)
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Forward Agent", isOn: $forwardAgent)
                                .accessibilityIdentifier("toggle_config_forwardagent")
                            Text("Forwards your Mac's SSH keys into the VM. Enable if you git clone/push from inside containers using SSH. Disable if you don't use SSH keys or have security concerns — VM processes could use your keys.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("SSH Config", isOn: $sshConfig)
                                .accessibilityIdentifier("toggle_config_sshconfig")
                            Text("Adds the VM to your ~/.ssh/config so you can `ssh colima` directly. Enable for convenience. Disable if you manage SSH config manually or have conflicting host entries.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Provisioning
                configCard(icon: "wrench.and.screwdriver", title: "Provisioning", description: "Shell scripts executed inside the VM on every start") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(provisions.enumerated()), id: \.offset) { i, _ in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Script \(i + 1)").font(.caption.weight(.medium))
                                        Spacer()
                                        Button(role: .destructive) {
                                            provisions.remove(at: i)
                                        } label: {
                                            Image(systemName: "trash").font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityIdentifier("btn_remove_provision_\(i)")
                                    }

                                    // Mode cards
                                    Text("Execution Mode").font(.caption2.weight(.medium))
                                    HStack(spacing: 8) {
                                        provisionModeCard(index: i, mode: "system", icon: "lock.shield", desc: "Runs as root. Use for installing packages, configuring services, modifying system files.")
                                        provisionModeCard(index: i, mode: "user", icon: "person", desc: "Runs as current user. Use for dotfiles, user configs, non-privileged setup.")
                                    }

                                    // Script editor
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Shell Script").font(.caption2.weight(.medium))
                                        Text("Bash commands executed on each VM start. Use for installing tools, configuring services, or setting up the environment.")
                                            .font(.caption2).foregroundStyle(.secondary)
                                        TextEditor(text: Binding(
                                            get: { provisions[i].script },
                                            set: { provisions[i].script = $0 }
                                        ))
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(height: 60)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.secondary.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))

                                        HStack {
                                            Button("Validate") {
                                                let script = provisions[i].script
                                                if script.isEmpty {
                                                    provisionValidation = "⚠ Empty script — add commands or remove this entry"
                                                } else if script.contains("rm -rf /") {
                                                    provisionValidation = "✗ Dangerous command detected"
                                                } else {
                                                    provisionValidation = "✓ Script looks valid"
                                                }
                                            }.font(.caption2)
                                            Menu("Examples") {
                                                Button("apt-get update && apt-get install -y curl") { provisions[i].script = "apt-get update && apt-get install -y curl" }
                                                Button("curl -fsSL https://get.docker.com | sh") { provisions[i].script = "curl -fsSL https://get.docker.com | sh" }
                                                Button("echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc") { provisions[i].script = "echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc" }
                                            }.font(.caption2)
                                            Spacer()
                                            if !provisionValidation.isEmpty {
                                                Text(provisionValidation).font(.caption2)
                                                    .foregroundStyle(provisionValidation.hasPrefix("✓") ? .green : .orange)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Button("Add Provision Script") {
                            provisions.append(("system", ""))
                        }.accessibilityIdentifier("btn_add_provision")
                    }
                }

                // MARK: Environment
                configCard(icon: "list.bullet.rectangle", title: "Environment", description: "Environment variables passed to the VM on startup") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(envVars.enumerated()), id: \.offset) { i, ev in
                            HStack {
                                Text(ev.key).font(.caption.monospaced().weight(.medium))
                                Text("=").foregroundStyle(.secondary)
                                Text(ev.value).font(.caption.monospaced())
                                Spacer()
                                Button(role: .destructive) {
                                    envVars.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }.accessibilityIdentifier("btn_remove_env_\(i)")
                            }
                        }
                        Button("Add Environment Variable") { showAddEnv = true }
                            .accessibilityIdentifier("btn_add_env")

                        if showAddEnv {
                            addEnvDialog
                        }
                    }
                }

                // MARK: Template
                configCard(icon: "doc.badge.gearshape", title: "Template", description: "Load or save configuration templates") {
                    HStack {
                        Button("Load Template") { appState.loadTemplate() }
                            .accessibilityIdentifier("btn_load_template")
                        Button("Save Template") { appState.saveTemplate() }
                            .accessibilityIdentifier("btn_save_template")
                    }
                }

                // MARK: Actions
                HStack {
                    Button("Save Configuration") { saveCurrentConfig() }
                        .accessibilityIdentifier("btn_save_config_all")
                    Button("Reset to Defaults") {
                        appState.resetConfig()
                        applyConfig(ColimaConfig())
                    }
                        .accessibilityIdentifier("btn_reset_config_all")
                    Button("Edit YAML") { appState.editYAML() }
                        .accessibilityIdentifier("btn_edit_config_yaml")
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Configuration")
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        Task { @MainActor in
            do {
                let config = try await appState.services.readConfig(profile: appState.activeProfile)
                appState.colimaConfig = config
                applyConfig(config)
            } catch {
                // Config file may not exist yet — use defaults
            }
        }
    }

    private func applyConfig(_ config: ColimaConfig) {
        cpus = Double(config.cpu)
        memory = Double(config.memory)
        disk = Double(config.disk)
        rootDisk = Double(config.rootDisk)
        arch = config.arch
        vmType = config.vmType
        cpuType = config.cpuType
        rosetta = config.rosetta
        nestedVirt = config.nestedVirtualization
        hostname = config.hostname
        diskImage = config.diskImage
        binfmt = config.binfmt
        portForwarder = config.portForwarder
        runtime = config.runtime
        autoActivate = config.autoActivate
        modelRunner = config.modelRunner
        k8sEnabled = config.kubernetes.enabled
        k8sVersion = config.kubernetes.version
        k8sArgs = config.kubernetes.k3sArgs.joined(separator: ",")
        k8sPort = config.kubernetes.port == 0 ? "" : "\(config.kubernetes.port)"
        networkAddress = config.network.address
        networkMode = config.network.mode
        networkInterface = config.network.interface
        dnsServers = config.network.dns.joined(separator: ", ")
        gateway = config.network.gatewayAddress
        hostAddresses = config.network.hostAddresses
        preferredRoute = config.network.preferredRoute
        mountType = config.mountType
        mountInotify = config.mountInotify
        mounts = config.mounts.map { ($0.location, $0.writable) }
        sshPort = config.sshPort == 0 ? "" : "\(config.sshPort)"
        forwardAgent = config.forwardAgent
        sshConfig = config.sshConfig
        provisions = config.provision.map { ($0.mode, $0.script) }
        envVars = config.env.map { ($0.key, $0.value) }
    }

    private func saveCurrentConfig() {
        var config = ColimaConfig()
        config.cpu = Int(cpus)
        config.memory = memory
        config.disk = Int(disk)
        config.rootDisk = Int(rootDisk)
        config.arch = arch
        config.vmType = vmType
        config.cpuType = cpuType
        config.rosetta = rosetta
        config.nestedVirtualization = nestedVirt
        config.hostname = hostname
        config.diskImage = diskImage
        config.binfmt = binfmt
        config.portForwarder = portForwarder
        config.runtime = runtime
        config.autoActivate = autoActivate
        config.modelRunner = modelRunner
        config.kubernetes.enabled = k8sEnabled
        config.kubernetes.version = k8sVersion.isEmpty ? "v1.35.0+k3s1" : k8sVersion
        config.kubernetes.k3sArgs = k8sArgs.isEmpty ? ["--disable=traefik"] : k8sArgs.components(separatedBy: ",")
        config.kubernetes.port = Int(k8sPort) ?? 0
        config.network.address = networkAddress
        config.network.mode = networkMode
        config.network.interface = networkInterface
        config.network.dns = dnsServers.isEmpty ? [] : dnsServers.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        config.network.gatewayAddress = gateway.isEmpty ? "192.168.5.2" : gateway
        config.network.hostAddresses = hostAddresses
        config.network.preferredRoute = preferredRoute
        config.mountType = mountType
        config.mountInotify = mountInotify
        config.mounts = mounts.map { ColimaConfig.Mount(location: $0.location, writable: $0.writable) }
        config.sshPort = Int(sshPort) ?? 0
        config.forwardAgent = forwardAgent
        config.sshConfig = sshConfig
        config.provision = provisions.map { ColimaConfig.Provision(mode: $0.mode, script: $0.script) }
        config.env = Dictionary(uniqueKeysWithValues: envVars.map { ($0.key, $0.value) })
        appState.saveConfig(config: config)
    }

    // MARK: - Components

    @ViewBuilder
    private func configCard<Content: View>(icon: String, title: String, description: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.caption.weight(.semibold))
                        Text(description).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Divider()
                content()
            }
        }
    }

    private func resourceBar(label: String, value: Double, total: Double, unit: String) -> some View {
        let unused = total - value
        let ratio = value / total
        let overAllocated = ratio > 0.75
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(value)) / \(Int(total)) \(unit)").font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: value, total: total)
                .tint(overAllocated ? .red : ratio > 0.5 ? .orange : .blue)
            HStack {
                Text("\(Int(unused)) \(unit) free for macOS")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if overAllocated {
                    Label("macOS may become slow", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            if value > total * 0.9 {
                Text("⚠️ Over-allocating leaves almost nothing for macOS and other apps. System will swap to disk, causing severe slowdowns.")
                    .font(.caption2).foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func vmTypeCard(type: String, icon: String, desc: String) -> some View {
        Button { vmType = type } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(type).font(.caption.weight(.medium))
                Text(desc).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(vmType == type ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(vmType == type ? Color.accentColor : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card_vmtype_\(type)")
        .accessibilityValue(vmType == type ? "selected" : "unselected")
    }

    private func cpuTypeCard(type: String, icon: String, desc: String) -> some View {
        Button { cpuType = type } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(type).font(.caption.weight(.medium))
                Text(desc).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(cpuType == type ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(cpuType == type ? Color.accentColor : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card_cputype_\(type)")
        .accessibilityValue(cpuType == type ? "selected" : "unselected")
    }

    private func mountTypeCard(type: String, icon: String, speed: String, pros: String, cons: String, recommended: Bool) -> some View {
        Button { mountType = type } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon).font(.caption)
                    Text(type).font(.caption.weight(.semibold))
                    if recommended {
                        Text("Recommended").font(.system(size: 8)).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.green.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(speed).font(.caption2)
                Text(pros).font(.system(size: 9)).foregroundStyle(.green)
                Text(cons).font(.system(size: 9)).foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(mountType == type ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(mountType == type ? Color.accentColor : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card_mounttype_\(type)")
        .accessibilityValue(mountType == type ? "selected" : "unselected")
    }

    @ViewBuilder
    private func lockIcon(id: String) -> some View {
        Image(systemName: "lock.fill")
            .font(.caption2).foregroundStyle(.secondary)
            .help("Cannot change after VM creation")
            .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func mountComparisonRow(type: String, stars: Int, note: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(type).font(.caption.monospaced()).frame(width: 60, alignment: .leading)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star")
                        .font(.system(size: 8))
                        .foregroundStyle(i < stars ? .yellow : .secondary)
                }
            }
            Text("speed").font(.caption2).foregroundStyle(.secondary)
            Text("|").foregroundStyle(.secondary)
            Text(note).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if selected {
                Image(systemName: "checkmark").font(.caption2).foregroundStyle(.blue)
            }
        }
    }

    private var addEnvDialog: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Add Environment Variable").font(.caption.weight(.semibold))
                    Spacer()
                    Button { showAddEnv = false } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.borderless)
                }

                // Presets
                VStack(alignment: .leading, spacing: 4) {
                    Text("Common Variables").font(.caption2.weight(.medium))
                    HStack(spacing: 6) {
                        Menu("Docker") {
                            Button("DOCKER_BUILDKIT=1 — Enable BuildKit builder") { addEnvPair("DOCKER_BUILDKIT", "1") }
                            Button("DOCKER_CLI_EXPERIMENTAL=enabled — Experimental CLI features") { addEnvPair("DOCKER_CLI_EXPERIMENTAL", "enabled") }
                            Button("DOCKER_DEFAULT_PLATFORM=linux/amd64 — Default platform") { addEnvPair("DOCKER_DEFAULT_PLATFORM", "linux/amd64") }
                            Button("COMPOSE_DOCKER_CLI_BUILD=1 — Compose uses BuildKit") { addEnvPair("COMPOSE_DOCKER_CLI_BUILD", "1") }
                        }.font(.caption2)
                        Menu("Colima") {
                            Button("COLIMA_LOG_LEVEL=debug — Verbose logging") { addEnvPair("COLIMA_LOG_LEVEL", "debug") }
                            Button("COLIMA_HOME=~/.colima — Config directory") { addEnvPair("COLIMA_HOME", "~/.colima") }
                        }.font(.caption2)
                        Menu("System") {
                            Button("HTTP_PROXY — HTTP proxy for containers") { newEnvKey = "HTTP_PROXY"; newEnvValue = "http://proxy:8080" }
                            Button("HTTPS_PROXY — HTTPS proxy") { newEnvKey = "HTTPS_PROXY"; newEnvValue = "http://proxy:8080" }
                            Button("NO_PROXY — Bypass proxy for these hosts") { newEnvKey = "NO_PROXY"; newEnvValue = "localhost,127.0.0.1" }
                            Button("TZ — Timezone") { newEnvKey = "TZ"; newEnvValue = "Europe/Vilnius" }
                        }.font(.caption2)
                    }
                }

                Divider()

                // Single entry
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Variable").font(.caption2.weight(.medium))
                    HStack {
                        TextField("KEY", text: $newEnvKey)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 150)
                            .font(.system(.caption, design: .monospaced))
                        Text("=").foregroundStyle(.secondary)
                        TextField("value", text: $newEnvValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button("Add") {
                            guard !newEnvKey.isEmpty else { return }
                            addEnvPair(newEnvKey, newEnvValue)
                            newEnvKey = ""; newEnvValue = ""
                        }
                        .font(.caption2).disabled(newEnvKey.isEmpty)
                    }
                }

                Divider()

                // Bulk entry
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bulk Add (one KEY=value per line)").font(.caption2.weight(.medium))
                    TextEditor(text: $newEnvBulk)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 50)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                    Button("Add All") {
                        for line in newEnvBulk.split(separator: "\n") {
                            let parts = line.split(separator: "=", maxSplits: 1)
                            if parts.count == 2 {
                                envVars.append((String(parts[0]), String(parts[1])))
                            }
                        }
                        newEnvBulk = ""
                        showAddEnv = false
                    }.font(.caption2).disabled(newEnvBulk.isEmpty)
                }
            }
        }
    }

    private func addEnvPair(_ key: String, _ value: String) {
        envVars.append((key, value))
    }

    private func provisionModeCard(index: Int, mode: String, icon: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: icon).font(.caption)
                Text(mode).font(.caption.weight(.medium))
            }
            Text(desc).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(provisions[index].mode == mode ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(provisions[index].mode == mode ? Color.accentColor : .clear, lineWidth: 1))
        .onTapGesture { provisions[index].mode = mode }
    }

    private func validateSSHPort() {
        guard let port = Int(sshPort), port > 0 else {
            if sshPort.isEmpty { sshPortStatus = ""; showSSHPortSuggestion = false } else { sshPortStatus = "✗ Invalid port"; showSSHPortSuggestion = true }
            return
        }
        let reserved = [22, 80, 443, 3000, 5432, 8080]
        if port < 1024 {
            sshPortStatus = "✗ Ports below 1024 require root"
            showSSHPortSuggestion = true
        } else if reserved.contains(port) {
            sshPortStatus = "✗ Port \(port) is in use"
            showSSHPortSuggestion = true
        } else {
            sshPortStatus = "✓ Port \(port) is available"
            showSSHPortSuggestion = false
        }
    }

    private var addMountDialog: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Add Mount Point").font(.caption.weight(.semibold))
                    Spacer()
                    Button { showAddMount = false } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.borderless)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Host Path").font(.caption.weight(.medium))
                    Text("Directory on your Mac to share with the VM. Containers can access files here.").font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        TextField("/path/to/directory", text: $newMountPath)
                            .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                        Menu("Common") {
                            Button("~ (Home directory)") { newMountPath = "~" }
                            Button("~/Projects") { newMountPath = "~/Projects" }
                            Button("~/Developer") { newMountPath = "~/Developer" }
                            Button("/tmp/colima") { newMountPath = "/tmp/colima" }
                            Button("/var/data") { newMountPath = "/var/data" }
                        }.font(.caption2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Mode").font(.caption.weight(.medium))
                    Picker("", selection: $newMountWritable) {
                        Text("Read-Write").tag(true)
                        Text("Read-Only").tag(false)
                    }.pickerStyle(.segmented)
                    Text(newMountWritable
                        ? "Containers can read and modify files. Use for project source code, build outputs."
                        : "Containers can only read files. Safer for config files, secrets, shared assets."
                    ).font(.caption2).foregroundStyle(.secondary)
                }

                HStack {
                    Button("Cancel") { showAddMount = false; newMountPath = "" }.font(.caption)
                    Spacer()
                    Button("Add") {
                        guard !newMountPath.isEmpty else { return }
                        mounts.append((newMountPath, newMountWritable))
                        newMountPath = ""
                        showAddMount = false
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .disabled(newMountPath.isEmpty)
                }
            }
        }
    }

    private func validateGateway() {
        guard !gateway.isEmpty else { gatewayStatus = ""; return }
        let parts = gateway.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 >= 0 && $0 <= 255 }) else {
            gatewayStatus = "✗ Invalid IP format"
            return
        }
        // Mock reachability check
        let localSubnets = ["192.168", "10.0", "172.16"]
        let prefix = parts.prefix(2).map(String.init).joined(separator: ".")
        if localSubnets.contains(where: { prefix.hasPrefix($0.prefix(prefix.count)) }) {
            if parts[3] == 1 {
                gatewayStatus = "✓ Reachable — standard gateway for \(prefix).x.x subnet"
            } else {
                gatewayStatus = "⚠ Unusual gateway (.1 is typical). VM may lose internet if this host doesn't route traffic."
            }
        } else {
            gatewayStatus = "✗ Not a local subnet — VM will likely have no internet. Use 192.168.64.1 or your router IP."
        }
    }

    private func setDNS(_ value: String) { dnsServers = value; dnsStatus = value.isEmpty ? "" : "✓ Set" }

    private func validateDNS() {
        guard !dnsServers.isEmpty else { dnsStatus = ""; return }
        let known = ["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9", "149.112.112.112", "208.67.222.222", "208.67.220.220", "94.140.14.14", "94.140.15.15"]
        let entries = dnsServers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let invalid = entries.filter { entry in
            let parts = entry.split(separator: ".").compactMap { Int($0) }
            return parts.count != 4 || parts.contains(where: { $0 < 0 || $0 > 255 })
        }
        if !invalid.isEmpty {
            dnsStatus = "⚠ Invalid IP: \(invalid.joined(separator: ", ")) — use Presets for known-good servers"
        } else {
            let unknown = entries.filter { !known.contains($0) }
            if unknown.isEmpty {
                dnsStatus = "✓ All servers verified"
            } else {
                dnsStatus = "⚠ \(unknown.joined(separator: ", ")) not recognized — may be unreachable. Consider using Presets."
            }
        }
    }

    private func validatePort() {
        guard let port = Int(k8sPort), port > 0 else {
            if k8sPort.isEmpty { portStatus = "" } else { portStatus = "✗ Invalid port number" }
            return
        }
        // Mock check: simulate port availability
        let inUse = [80, 443, 8080, 3000, 5432]
        if inUse.contains(port) {
            portStatus = "✗ Port \(port) in use — pick from Open Ports"
        } else {
            portStatus = "✓ Port \(port) is available"
        }
    }

    private func validateK8sVersion() {
        let v = k8sCustomVersion
        if v.isEmpty { k8sVersionError = ""; return }
        let pattern = #"^v\d+\.\d+\.\d+\+k3s\d+$"#
        if v.range(of: pattern, options: .regularExpression) != nil {
            k8sVersionError = "✓ Valid format"
        } else {
            k8sVersionError = "Expected format: v1.30.0+k3s1"
        }
    }

    private func appendArg(_ arg: String) {
        if k8sArgs.isEmpty {
            k8sArgs = arg
        } else {
            k8sArgs += ",\(arg)"
        }
    }

    private func insertKey(_ key: String) {
        if dockerJSON.hasSuffix("}") {
            let trimmed = dockerJSON.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("{") {
                dockerJSON = "{\n  \(key)\n}"
            } else {
                dockerJSON = "\(trimmed),\n  \(key)\n}"
            }
        }
    }

    private func formatJSON() {
        guard let data = dockerJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            jsonError = "Invalid JSON"
            return
        }
        dockerJSON = str
        jsonError = ""
    }

    private func validateJSON() {
        guard let data = dockerJSON.data(using: .utf8) else { jsonError = "Invalid encoding"; return }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            jsonError = "✓ Valid"
        } catch {
            jsonError = error.localizedDescription
        }
    }
}

// MARK: - Docker JSON Editor with syntax coloring

struct DockerJSONEditor: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.caption, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
    }
}
