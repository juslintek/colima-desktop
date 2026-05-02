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

    var body: some View {
        Form {
            // MARK: VM Resources
            Section("VM Resources") {
                HStack {
                    Text("CPUs"); Spacer()
                    Stepper("\(Int(cpus))", value: $cpus, in: 1...16)
                        .accessibilityIdentifier("field_config_cpus")
                }
                HStack {
                    Text("Memory (GiB)"); Spacer()
                    Stepper("\(Int(memory))", value: $memory, in: 1...64)
                        .accessibilityIdentifier("field_config_memory")
                }
                HStack {
                    Text("Disk (GiB)"); Spacer()
                    Stepper("\(Int(disk))", value: $disk, in: 10...500)
                        .accessibilityIdentifier("field_config_disk")
                }
                HStack {
                    Text("Root Disk (GiB)"); Spacer()
                    Stepper("\(Int(rootDisk))", value: $rootDisk, in: 10...500)
                        .accessibilityIdentifier("field_config_rootdisk")
                }
            }

            // MARK: VM Settings
            Section("VM Settings") {
                HStack {
                    Picker("Architecture", selection: $arch) {
                        Text("host").tag("host"); Text("aarch64").tag("aarch64"); Text("x86_64").tag("x86_64")
                    }.accessibilityIdentifier("field_config_arch")
                    Image(systemName: "lock.fill").accessibilityIdentifier("lock_config_arch")
                }
                HStack {
                    Picker("VM Type", selection: $vmType) {
                        Text("qemu").tag("qemu"); Text("vz").tag("vz"); Text("krunkit").tag("krunkit")
                    }.accessibilityIdentifier("field_config_vmtype")
                    Image(systemName: "lock.fill").accessibilityIdentifier("lock_config_vmtype")
                }
                TextField("CPU Type", text: $cpuType).accessibilityIdentifier("field_config_cputype")
                Toggle("Rosetta", isOn: $rosetta).accessibilityIdentifier("toggle_config_rosetta")
                Toggle("Nested Virtualization", isOn: $nestedVirt).accessibilityIdentifier("toggle_config_nestedvirt")
                TextField("Hostname", text: $hostname).accessibilityIdentifier("field_config_hostname")
                TextField("Disk Image", text: $diskImage).accessibilityIdentifier("field_config_diskimage")
                Toggle("Binfmt", isOn: $binfmt).accessibilityIdentifier("toggle_config_binfmt")
                Toggle("Foreground", isOn: $foreground).accessibilityIdentifier("toggle_config_foreground")
                Picker("Port Forwarder", selection: $portForwarder) {
                    Text("ssh").tag("ssh"); Text("grpc").tag("grpc"); Text("none").tag("none")
                }.accessibilityIdentifier("field_config_portforwarder")
            }

            // MARK: Runtime
            Section("Runtime") {
                HStack {
                    Picker("Runtime", selection: $runtime) {
                        Text("docker").tag("docker"); Text("containerd").tag("containerd"); Text("incus").tag("incus")
                    }.accessibilityIdentifier("field_config_runtime")
                    Image(systemName: "lock.fill").accessibilityIdentifier("lock_config_runtime")
                }
                Toggle("Auto Activate", isOn: $autoActivate).accessibilityIdentifier("toggle_config_autoactivate")
                Picker("Model Runner", selection: $modelRunner) {
                    Text("docker").tag("docker"); Text("ramalama").tag("ramalama")
                }.accessibilityIdentifier("field_config_modelrunner")
                VStack(alignment: .leading) {
                    Text("Docker Daemon Config (JSON)")
                    TextEditor(text: $dockerJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .accessibilityIdentifier("field_config_dockerjson")
                }
            }

            // MARK: Kubernetes
            Section("Kubernetes") {
                Toggle("Enabled", isOn: $k8sEnabled).accessibilityIdentifier("toggle_config_k8s")
                TextField("Version", text: $k8sVersion).accessibilityIdentifier("field_config_k8sversion")
                VStack(alignment: .leading) {
                    Text("k3s Args (comma-separated)")
                    TextEditor(text: $k8sArgs)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 50)
                        .accessibilityIdentifier("field_config_k3sargs")
                }
                TextField("API Port", text: $k8sPort).accessibilityIdentifier("field_config_k8sport")
            }

            // MARK: Network
            Section("Network") {
                Toggle("Network Address", isOn: $networkAddress).accessibilityIdentifier("toggle_config_networkaddress")
                Picker("Network Mode", selection: $networkMode) {
                    Text("shared").tag("shared"); Text("bridged").tag("bridged")
                }.accessibilityIdentifier("field_config_networkmode")
                TextField("Interface", text: $networkInterface).accessibilityIdentifier("field_config_interface")
                TextField("DNS Servers", text: $dnsServers).accessibilityIdentifier("field_config_dns")
                VStack(alignment: .leading) {
                    Text("DNS Hosts (key=value per line)")
                    TextEditor(text: $dnsHosts)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 50)
                        .accessibilityIdentifier("field_config_dnshosts")
                }
                TextField("Gateway", text: $gateway).accessibilityIdentifier("field_config_gateway")
                Toggle("Host Addresses", isOn: $hostAddresses).accessibilityIdentifier("toggle_config_hostaddresses")
                Toggle("Preferred Route", isOn: $preferredRoute).accessibilityIdentifier("toggle_config_preferredroute")
            }

            // MARK: Volume Mounts
            Section("Volume Mounts") {
                HStack {
                    Picker("Mount Type", selection: $mountType) {
                        Text("sshfs").tag("sshfs"); Text("9p").tag("9p"); Text("virtiofs").tag("virtiofs")
                    }.accessibilityIdentifier("field_config_mounttype")
                    Image(systemName: "lock.fill").accessibilityIdentifier("lock_config_mounttype")
                }
                Toggle("Inotify", isOn: $mountInotify).accessibilityIdentifier("toggle_config_inotify")
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

            // MARK: SSH
            Section("SSH") {
                TextField("SSH Port", text: $sshPort).accessibilityIdentifier("field_config_sshport")
                Toggle("Forward Agent", isOn: $forwardAgent).accessibilityIdentifier("toggle_config_forwardagent")
                Toggle("SSH Config", isOn: $sshConfig).accessibilityIdentifier("toggle_config_sshconfig")
            }

            // MARK: Provisioning
            Section("Provisioning") {
                ForEach(Array(provisions.enumerated()), id: \.offset) { i, p in
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

            // MARK: Environment
            Section("Environment") {
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

            // MARK: Template
            Section("Template") {
                HStack {
                    Button("Load Template") { appState.loadTemplate() }
                        .accessibilityIdentifier("btn_load_template")
                    Button("Save Template") { appState.saveTemplate() }
                        .accessibilityIdentifier("btn_save_template")
                }
            }

            // MARK: Actions
            Section {
                HStack {
                    Button("Save Configuration") { appState.saveConfig() }
                        .accessibilityIdentifier("btn_save_config_all")
                    Button("Reset to Defaults") { appState.resetConfig() }
                        .accessibilityIdentifier("btn_reset_config_all")
                    Button("Edit YAML") { appState.editYAML() }
                        .accessibilityIdentifier("btn_edit_config_yaml")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configuration")
    }
}
