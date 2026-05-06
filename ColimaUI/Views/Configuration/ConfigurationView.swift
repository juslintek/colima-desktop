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
    @State private var cpuType = ""
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

    // Kubernetes
    @State private var k8sEnabled = false
    @State private var k8sVersion = ""
    @State private var k8sArgs = ""
    @State private var k8sPort = ""

    // Network
    @State private var networkAddress = false
    @State private var networkMode = "shared"
    @State private var networkInterface = ""
    @State private var dnsServers = ""
    @State private var dnsHosts = "db.local=192.168.1.10"
    @State private var gateway = ""
    @State private var hostAddresses = false
    @State private var preferredRoute = false

    // Volume Mounts
    @State private var mountType = "sshfs"
    @State private var mountInotify = true
    @State private var disableMounts = false
    @State private var mounts: [(location: String, writable: Bool)] = [
        ("~", true), ("/tmp/colima", true)
    ]

    // SSH
    @State private var sshPort = ""
    @State private var forwardAgent = false
    @State private var sshConfig = true

    // Provisioning
    @State private var provisions: [(mode: String, script: String)] = [
        ("system", "apt-get update")
    ]

    // Environment
    @State private var envVars: [(key: String, value: String)] = [
        ("DOCKER_BUILDKIT", "1")
    ]

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
                        // Architecture
                        HStack {
                            Picker("Architecture", selection: $arch) {
                                Text("host").tag("host"); Text("aarch64").tag("aarch64"); Text("x86_64").tag("x86_64")
                            }.accessibilityIdentifier("field_config_arch")
                            lockIcon(id: "lock_config_arch")
                        }

                        // VM Type cards
                        Text("VM Type").font(.caption.weight(.medium))
                        HStack(spacing: 8) {
                            vmTypeCard(type: "qemu", icon: "desktopcomputer", desc: "Universal — works everywhere, supports x86 emulation")
                            vmTypeCard(type: "vz", icon: "apple.logo", desc: "Native — Apple's framework, fastest I/O on Apple Silicon")
                            vmTypeCard(type: "krunkit", icon: "gpu", desc: "GPU — lightweight with Metal GPU access for AI")
                        }
                        .accessibilityIdentifier("field_config_vmtype")
                        HStack {
                            Spacer()
                            lockIcon(id: "lock_config_vmtype")
                        }

                        TextField("CPU Type", text: $cpuType).accessibilityIdentifier("field_config_cputype")

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

                        Toggle("Nested Virtualization", isOn: $nestedVirt).withTooltip(ConfigTooltips.nestedVirt)
                            .accessibilityIdentifier("toggle_config_nestedvirt")
                        TextField("Hostname", text: $hostname).accessibilityIdentifier("field_config_hostname")
                        TextField("Disk Image", text: $diskImage).accessibilityIdentifier("field_config_diskimage")
                        Toggle("Binfmt", isOn: $binfmt).withTooltip(ConfigTooltips.binfmt)
                            .accessibilityIdentifier("toggle_config_binfmt")
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
                        VStack(alignment: .leading) {
                            Text("Docker Daemon Config (JSON)").font(.caption)
                            TextEditor(text: $dockerJSON)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 80)
                                .accessibilityIdentifier("field_config_dockerjson")
                        }
                    }
                }

                // MARK: Kubernetes
                configCard(icon: "helm", title: "Kubernetes", description: "Enable k3s cluster inside the VM") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enabled", isOn: $k8sEnabled).withTooltip(ConfigTooltips.kubernetes)
                            .accessibilityIdentifier("toggle_config_k8s")
                        TextField("Version", text: $k8sVersion).accessibilityIdentifier("field_config_k8sversion")
                        VStack(alignment: .leading) {
                            Text("k3s Args (comma-separated)").font(.caption)
                            TextEditor(text: $k8sArgs)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 50)
                                .accessibilityIdentifier("field_config_k3sargs")
                        }
                        TextField("API Port", text: $k8sPort).accessibilityIdentifier("field_config_k8sport")
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

                        Toggle("Network Address", isOn: $networkAddress).withTooltip(ConfigTooltips.networkAddress)
                            .accessibilityIdentifier("toggle_config_networkaddress")
                        Picker("Network Mode", selection: $networkMode) {
                            Text("shared").tag("shared"); Text("bridged").tag("bridged")
                        }.accessibilityIdentifier("field_config_networkmode")
                        TextField("Interface", text: $networkInterface).accessibilityIdentifier("field_config_interface")

                        // DNS group
                        GroupBox("DNS Settings") {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("DNS Servers", text: $dnsServers).accessibilityIdentifier("field_config_dns")
                                VStack(alignment: .leading) {
                                    Text("DNS Hosts (key=value per line)").font(.caption2)
                                    TextEditor(text: $dnsHosts)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(height: 50)
                                        .accessibilityIdentifier("field_config_dnshosts")
                                }
                            }
                        }

                        TextField("Gateway", text: $gateway).accessibilityIdentifier("field_config_gateway")
                        Toggle("Host Addresses", isOn: $hostAddresses).accessibilityIdentifier("toggle_config_hostaddresses")
                        Toggle("Preferred Route", isOn: $preferredRoute).accessibilityIdentifier("toggle_config_preferredroute")
                    }
                }

                // MARK: Volume Mounts
                configCard(icon: "externaldrive", title: "Volume Mounts", description: "Share host directories with the VM") {
                    VStack(alignment: .leading, spacing: 8) {
                        // Mount type comparison
                        VStack(alignment: .leading, spacing: 4) {
                            mountComparisonRow(type: "virtiofs", stars: 5, note: "Requires vz", selected: mountType == "virtiofs")
                            mountComparisonRow(type: "9p", stars: 3, note: "Works with qemu", selected: mountType == "9p")
                            mountComparisonRow(type: "sshfs", stars: 2, note: "Most compatible", selected: mountType == "sshfs")
                        }
                        .padding(8).background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        HStack {
                            Picker("Mount Type", selection: $mountType) {
                                Text("sshfs").tag("sshfs"); Text("9p").tag("9p"); Text("virtiofs").tag("virtiofs")
                            }.accessibilityIdentifier("field_config_mounttype")
                            TooltipButton(info: ConfigTooltips.mountType)
                            lockIcon(id: "lock_config_mounttype")
                        }
                        Toggle("Inotify", isOn: $mountInotify).withTooltip(ConfigTooltips.inotify)
                            .accessibilityIdentifier("toggle_config_inotify")
                        Toggle("Disable Mounts", isOn: $disableMounts).accessibilityIdentifier("toggle_config_disablemounts")

                        ForEach(Array(mounts.enumerated()), id: \.offset) { i, m in
                            HStack {
                                Text(m.location)
                                Spacer()
                                Text(m.writable ? "rw" : "ro").foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    mounts.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }.accessibilityIdentifier("btn_remove_mount_\(i)")
                            }
                        }
                        Button("Add Mount") {
                            mounts.append(("/new/path", true))
                        }.accessibilityIdentifier("btn_add_mount")
                    }
                }

                // MARK: SSH
                configCard(icon: "terminal", title: "SSH", description: "SSH access to the VM") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("SSH Port", text: $sshPort).accessibilityIdentifier("field_config_sshport")
                        Toggle("Forward Agent", isOn: $forwardAgent).withTooltip(ConfigTooltips.forwardAgent)
                            .accessibilityIdentifier("toggle_config_forwardagent")
                        Toggle("SSH Config", isOn: $sshConfig).accessibilityIdentifier("toggle_config_sshconfig")
                    }
                }

                // MARK: Provisioning
                configCard(icon: "wrench.and.screwdriver", title: "Provisioning", description: "Scripts to run on VM startup") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(provisions.enumerated()), id: \.offset) { i, _ in
                            VStack(alignment: .leading) {
                                HStack {
                                    Picker("Mode", selection: Binding(
                                        get: { provisions[i].mode },
                                        set: { provisions[i].mode = $0 }
                                    )) {
                                        Text("system").tag("system"); Text("user").tag("user")
                                    }.frame(width: 150)
                                    Spacer()
                                    Button(role: .destructive) {
                                        provisions.remove(at: i)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }.accessibilityIdentifier("btn_remove_provision_\(i)")
                                }
                                TextEditor(text: Binding(
                                    get: { provisions[i].script },
                                    set: { provisions[i].script = $0 }
                                ))
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 40)
                            }
                        }
                        Button("Add Provision Script") {
                            provisions.append(("system", ""))
                        }.accessibilityIdentifier("btn_add_provision")
                    }
                }

                // MARK: Environment
                configCard(icon: "list.bullet.rectangle", title: "Environment", description: "Environment variables passed to the VM") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(envVars.enumerated()), id: \.offset) { i, ev in
                            HStack {
                                Text("\(ev.key)=\(ev.value)")
                                Spacer()
                                Button(role: .destructive) {
                                    envVars.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }.accessibilityIdentifier("btn_remove_env_\(i)")
                            }
                        }
                        Button("Add Environment Variable") {
                            envVars.append(("KEY", "value"))
                        }.accessibilityIdentifier("btn_add_env")
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
                    Button("Save Configuration") { appState.saveConfig() }
                        .accessibilityIdentifier("btn_save_config_all")
                    Button("Reset to Defaults") { appState.resetConfig() }
                        .accessibilityIdentifier("btn_reset_config_all")
                    Button("Edit YAML") { appState.editYAML() }
                        .accessibilityIdentifier("btn_edit_config_yaml")
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Configuration")
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

    @ViewBuilder
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
        .onTapGesture { vmType = type }
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
}
