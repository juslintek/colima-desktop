import SwiftUI

// MARK: - Tooltip Data

struct TooltipInfo {
    let title: String
    let description: String
    let recommendation: String?
    let impact: String?
}

// MARK: - Tooltip Definitions

enum ConfigTooltips {
    static let vmType = TooltipInfo(
        title: "VM Type",
        description: "Determines the virtualization technology used to run the Linux VM.",
        recommendation: "Use 'vz' on Apple Silicon (macOS 13+) for best performance. Use 'qemu' for x86 emulation or older Macs.",
        impact: "Cannot be changed after VM creation. Requires delete + recreate."
    )
    static let cpus = TooltipInfo(
        title: "CPUs",
        description: "Number of CPU cores allocated to the VM.",
        recommendation: "Half your total cores is a good default. Increase for builds, decrease on battery.",
        impact: "Requires VM restart to apply."
    )
    static let memory = TooltipInfo(
        title: "Memory",
        description: "RAM allocated to the VM in GiB.",
        recommendation: "8 GiB for general development. 16+ GiB for AI/ML workloads or many containers.",
        impact: "Requires VM restart. Over-allocating starves macOS."
    )
    static let disk = TooltipInfo(
        title: "Disk",
        description: "Maximum disk size for the VM. Grows dynamically up to this limit.",
        recommendation: "100 GiB for most workloads. Increase if you pull many large images.",
        impact: "Can only be increased, never decreased."
    )
    static let mountType = TooltipInfo(
        title: "Mount Type",
        description: "How host files are shared with the VM.",
        recommendation: "virtiofs: fastest, requires vz. 9p: moderate speed, works with qemu. sshfs: slowest but most compatible.",
        impact: "Cannot be changed after creation. Affects file I/O performance significantly."
    )
    static let rosetta = TooltipInfo(
        title: "Rosetta",
        description: "Enables Apple's x86→ARM translation layer inside the VM.",
        recommendation: "Enable if you need to run x86 Docker images on Apple Silicon. 5x faster than QEMU emulation.",
        impact: "Requires vz VM type and macOS 13+."
    )
    static let runtime = TooltipInfo(
        title: "Container Runtime",
        description: "The container engine running inside the VM.",
        recommendation: "docker: most compatible, works with docker-compose. containerd: lighter, used by Kubernetes. incus: for system containers/VMs.",
        impact: "Cannot be changed after creation."
    )
    static let kubernetes = TooltipInfo(
        title: "Kubernetes",
        description: "Runs a lightweight k3s cluster inside the VM.",
        recommendation: "Enable only if you need it — adds ~256 MB memory overhead.",
        impact: "Can be toggled without recreating the VM."
    )
    static let networkAddress = TooltipInfo(
        title: "Network Address",
        description: "Assigns a reachable IP to the VM on your local network.",
        recommendation: "Enable if you need to access VM services from other devices on your LAN.",
        impact: "Requires sudo on first use. May prompt for password."
    )
    static let inotify = TooltipInfo(
        title: "Inotify",
        description: "Enables filesystem change notifications for mounted volumes.",
        recommendation: "Enable for hot-reload in development (webpack, nodemon, etc.).",
        impact: "Slight CPU overhead from watching file changes."
    )
    static let forwardAgent = TooltipInfo(
        title: "SSH Agent Forwarding",
        description: "Forwards your SSH keys into the VM for git operations.",
        recommendation: "Enable if you git clone/push from inside containers.",
        impact: "Security consideration: VM processes can use your SSH keys."
    )
    static let nestedVirt = TooltipInfo(
        title: "Nested Virtualization",
        description: "Allows running VMs inside the Colima VM.",
        recommendation: "Enable for Docker-in-Docker, Kubernetes-in-Docker, or testing VM tools.",
        impact: "Requires vz VM type. Slight performance overhead."
    )
    static let portForwarder = TooltipInfo(
        title: "Port Forwarder",
        description: "How container ports are exposed to the host.",
        recommendation: "ssh: reliable default. grpc: faster for many ports. none: manual forwarding only.",
        impact: "Affects how you access container services from localhost."
    )
    static let binfmt = TooltipInfo(
        title: "Binfmt",
        description: "Registers QEMU user-mode emulators for cross-architecture execution.",
        recommendation: "Keep enabled for multi-arch Docker builds (buildx).",
        impact: "Minimal overhead. Required for building x86 images on ARM."
    )
}

// MARK: - Tooltip Button View

struct TooltipButton: View {
    let info: TooltipInfo
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(info.title).font(.headline)
                Text(info.description).font(.body)
                if let rec = info.recommendation {
                    Label(rec, systemImage: "lightbulb")
                        .font(.callout)
                        .foregroundStyle(.blue)
                }
                if let impact = info.impact {
                    Label(impact, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .frame(maxWidth: 320)
        }
        .accessibilityIdentifier("tooltip_\(info.title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}

// MARK: - View Modifier for Settings with Tooltip

struct SettingWithTooltip: ViewModifier {
    let tooltip: TooltipInfo

    func body(content: Content) -> some View {
        HStack(spacing: 4) {
            content
            TooltipButton(info: tooltip)
        }
    }
}

extension View {
    func withTooltip(_ info: TooltipInfo) -> some View {
        modifier(SettingWithTooltip(tooltip: info))
    }
}
