import SwiftUI

// MARK: - Wizard Data

enum WorkloadType: String, CaseIterable, Identifiable {
    case webDev = "Docker containers for web development"
    case kubernetes = "Kubernetes local cluster"
    case aiml = "AI/ML model development"
    case crossPlatform = "Cross-platform builds (x86 on ARM)"
    case multiEnv = "Multiple isolated environments"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .webDev: return "globe"
        case .kubernetes: return "helm"
        case .aiml: return "brain"
        case .crossPlatform: return "cpu"
        case .multiEnv: return "square.stack.3d.up"
        }
    }
}

enum ResourceTier: String, CaseIterable, Identifiable {
    case light = "Light — laptop on battery"
    case moderate = "Moderate — daily development"
    case heavy = "Heavy — builds & AI workloads"
    case custom = "Let me choose manually"
    var id: String { rawValue }
    var cpus: Int { switch self { case .light: return 2; case .moderate: return 4; case .heavy: return 8; case .custom: return 4 } }
    var memory: Int { switch self { case .light: return 4; case .moderate: return 8; case .heavy: return 16; case .custom: return 8 } }
    var icon: String { switch self { case .light: return "battery.25"; case .moderate: return "battery.75"; case .heavy: return "battery.100"; case .custom: return "slider.horizontal.3" } }
}

enum MountChoice: String, CaseIterable, Identifiable {
    case projects = "Yes, my projects folder"
    case hotReload = "Yes, with hot-reload support"
    case none = "No, containers are self-contained"
    var id: String { rawValue }
    var mountType: String { switch self { case .projects, .hotReload: return "virtiofs"; case .none: return "sshfs" } }
    var inotify: Bool { self == .hotReload }
}

// MARK: - Guided Setup Wizard

struct GuidedSetupWizard: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var step = 0
    @State private var selectedWorkloads: Set<WorkloadType> = []
    @State private var resourceTier: ResourceTier = .moderate
    @State private var mountChoice: MountChoice = .projects
    @State private var enableK8s = false
    @State private var enableCompose = true

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Content
            Group {
                switch step {
                case 0: workloadStep
                case 1: resourceStep
                case 2: mountStep
                case 3: extrasStep
                default: summaryStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)

            Divider()

            // Navigation
            HStack {
                if step > 0 && step <= totalSteps {
                    Button("Back") { withAnimation { step -= 1 } }
                        .accessibilityIdentifier("btn_wizard_back")
                }
                Spacer()
                if step < totalSteps {
                    Button("Continue") { withAnimation { step += 1 } }
                        .buttonStyle(.borderedProminent)
                        .disabled(step == 0 && selectedWorkloads.isEmpty)
                        .accessibilityIdentifier("btn_wizard_next")
                } else {
                    Button("Apply & Start") { applyConfig() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("btn_wizard_apply")
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
        .accessibilityIdentifier("sheet_guided_setup")
    }

    // MARK: - Step 1: Workload

    private var workloadStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What will you use Colima for?").font(.title2.weight(.semibold))
            Text("Select all that apply. This helps us configure optimal settings.").foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(WorkloadType.allCases) { w in
                    Button {
                        if selectedWorkloads.contains(w) { selectedWorkloads.remove(w) }
                        else { selectedWorkloads.insert(w) }
                    } label: {
                        HStack {
                            Image(systemName: w.icon).frame(width: 24)
                            Text(w.rawValue)
                            Spacer()
                            if selectedWorkloads.contains(w) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                        .padding(10)
                        .background(selectedWorkloads.contains(w) ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn_workload_\(w.rawValue.prefix(10).filter { $0.isLetter })")
                }
            }
        }
    }

    // MARK: - Step 2: Resources

    private var resourceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How much resources can you spare?").font(.title2.weight(.semibold))
            Text("You have \(ProcessInfo.processInfo.processorCount) CPU cores and \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB RAM.").foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(ResourceTier.allCases) { tier in
                    Button { resourceTier = tier } label: {
                        HStack {
                            Image(systemName: tier.icon).frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(tier.rawValue)
                                Text("\(tier.cpus) CPU, \(tier.memory) GB RAM").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if resourceTier == tier {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                        .padding(10)
                        .background(resourceTier == tier ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn_resource_\(tier.id.prefix(8).filter { $0.isLetter })")
                }
            }
        }
    }

    // MARK: - Step 3: Mounts

    private var mountStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Do you need file sharing with the VM?").font(.title2.weight(.semibold))
            Text("File sharing lets containers access your local project files.").foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(MountChoice.allCases) { choice in
                    Button { mountChoice = choice } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(choice.rawValue)
                                Text("Recommended: \(choice.mountType)\(choice.inotify ? " + inotify" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if mountChoice == choice {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                        .padding(10)
                        .background(mountChoice == choice ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn_mount_\(choice.id.prefix(8).filter { $0.isLetter })")
                }
            }
        }
    }

    // MARK: - Step 4: Extras

    private var extrasStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Additional features").font(.title2.weight(.semibold))
            Text("These can be changed later in Configuration.").foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Toggle(isOn: $enableK8s) {
                    VStack(alignment: .leading) {
                        Text("Enable Kubernetes")
                        Text("Runs k3s cluster. Adds ~256 MB memory overhead.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("toggle_wizard_k8s")

                Toggle(isOn: $enableCompose) {
                    VStack(alignment: .leading) {
                        Text("Install Docker Compose")
                        Text("Required for docker-compose.yml files.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("toggle_wizard_compose")
            }
            .padding(.top, 8)

            Spacer()

            // Summary preview
            GroupBox("Configuration Preview") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("VM Type").foregroundStyle(.secondary); Text(vmTypeRecommendation) }
                    GridRow { Text("CPUs").foregroundStyle(.secondary); Text("\(resourceTier.cpus)") }
                    GridRow { Text("Memory").foregroundStyle(.secondary); Text("\(resourceTier.memory) GiB") }
                    GridRow { Text("Mount").foregroundStyle(.secondary); Text(mountChoice.mountType) }
                    GridRow { Text("Kubernetes").foregroundStyle(.secondary); Text(enableK8s ? "Enabled" : "Disabled") }
                }
                .font(.callout)
            }
        }
    }

    // MARK: - Summary (after step 4)

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                Text("Your environment is configured!").font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 12) {
                summaryRow(key: "VM Type", value: vmTypeRecommendation, reason: "Apple's native virtualization for best performance on your Mac")
                summaryRow(key: "Mount Type", value: mountChoice.mountType, reason: "Fastest file sharing for \(mountChoice == .none ? "no mounts needed" : "your development workflow")")
                summaryRow(key: "Resources", value: "\(resourceTier.cpus) CPU, \(resourceTier.memory) GB RAM, 100 GB disk", reason: "Balanced for \(selectedWorkloads.first?.rawValue ?? "development"). Leaves plenty for macOS.")
                summaryRow(key: "Runtime", value: "Docker", reason: "Standard container runtime. Compatible with all docker-compose files.")
                summaryRow(key: "Kubernetes", value: enableK8s ? "Enabled" : "Disabled", reason: enableK8s ? "k3s cluster for local development" : "Can be enabled later from Configuration.")
            }
        }
    }

    private func summaryRow(key: String, value: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(key).fontWeight(.medium)
                Spacer()
                Text(value).foregroundStyle(.blue)
            }
            Text(reason).font(.caption).foregroundStyle(.secondary)
            Divider()
        }
    }

    // MARK: - Logic

    private var vmTypeRecommendation: String {
        #if arch(arm64)
        return "vz"
        #else
        return "qemu"
        #endif
    }

    private func applyConfig() {
        appState.showToast("Environment configured! Starting Colima...")
        isPresented = false
    }
}
