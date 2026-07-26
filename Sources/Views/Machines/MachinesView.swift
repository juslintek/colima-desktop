import SwiftUI

// MARK: - Mock VM Data

struct MockVM: Identifiable {
    let id: String
    let name: String
    let os: VMOS
    let status: String
    let cpus: Int
    let memory: Int
    let disk: Int
    let arch: String

    enum VMOS: String {
        case linux, macos, windows
        var icon: String {
            switch self { case .linux: return "server.rack"; case .macos: return "apple.logo"; case .windows: return "pc" }
        }
        var color: Color {
            switch self { case .linux: return .orange; case .macos: return .blue; case .windows: return .cyan }
        }
    }
}

// MARK: - Machines View

struct MachinesView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var searchText = ""

    private var filtered: [MockVM] {
        searchText.isEmpty ? appState.machines : appState.machines.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Spacer()
                Button { showCreateSheet = true } label: {
                    Label("New Machine", systemImage: "plus")
                }
                .accessibilityIdentifier("btn_create_machine")
            }
            .padding(8)

            // VM List
            List(selection: $appState.selectedMachine) {
                ForEach(filtered) { vm in
                    vmRow(vm)
                        .tag(vm.id)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Machines")
        .navigationSubtitle("\(appState.machines.filter { $0.status == "running" }.count) running")
        .sheet(isPresented: $showCreateSheet) { CreateMachineSheet() }
    }

    private func vmRow(_ vm: MockVM) -> some View {
        HStack(spacing: 10) {
            Image(systemName: vm.os.icon)
                .foregroundStyle(vm.os.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.name).font(.body.weight(.medium))
                Text("\(vm.os.rawValue.capitalized) · \(vm.arch) · \(vm.cpus) CPU · \(vm.memory) GB")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(vm.status == "running" ? .green : .gray)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Machine lifecycle is read-only in this build") {}
                .disabled(true)
        }
        .accessibilityIdentifier("row_machine_\(vm.name)")
    }
}

// MARK: - Machine Detail View

struct MachineDetailView: View {
    let vm: MockVM
    @State private var selectedTab: Tab = .info

    enum Tab: String, CaseIterable { case info = "Info", stats = "Stats", logs = "Logs", terminal = "Terminal", files = "Files" }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: vm.os.icon).foregroundStyle(vm.os.color)
                Text(vm.name).font(.title3.weight(.semibold))
                Circle().fill(vm.status == "running" ? .green : .gray).frame(width: 8, height: 8)
                Spacer()
                Text("Inventory only").font(.caption).foregroundStyle(.secondary)
            }
            .padding()

            // Tabs
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Content
            Group {
                switch selectedTab {
                case .info: machineInfo
                case .stats: unavailable("Machine stats are not exposed by the current daemon contract.", icon: "chart.xyaxis.line")
                case .logs: unavailable("Machine logs are not exposed by the current daemon contract.", icon: "doc.text")
                case .terminal: unavailable("Machine shell execution is not exposed by the current daemon contract.", icon: "terminal")
                case .files: unavailable("Machine file browsing is not exposed by the current daemon contract.", icon: "folder")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var machineInfo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("System") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { Text("OS").foregroundStyle(.secondary); Text(vm.os.rawValue.capitalized) }
                        GridRow { Text("Architecture").foregroundStyle(.secondary); Text(vm.arch) }
                        GridRow { Text("Status").foregroundStyle(.secondary); Text(vm.status) }
                    }.font(.caption)
                }
                GroupBox("Resources") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { Text("CPUs").foregroundStyle(.secondary); Text("\(vm.cpus) cores") }
                        GridRow { Text("Memory").foregroundStyle(.secondary); Text("\(vm.memory) GiB") }
                        GridRow { Text("Disk").foregroundStyle(.secondary); Text("\(vm.disk) GiB") }
                    }.font(.caption)
                }
                Text("Network address and SSH endpoint are not included in the machine inventory response.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }.padding()
        }
    }

    private func unavailable(_ message: String, icon: String) -> some View {
        ContentUnavailableView("Unavailable", systemImage: icon, description: Text(message))
    }
}

// MARK: - Create Machine Sheet

struct CreateMachineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var os: MockVM.VMOS = .linux
    @State private var distro = "Ubuntu 24.04"
    @State private var cpus: Double = 4
    @State private var memory: Double = 8
    @State private var disk: Double = 50
    @State private var arch = "aarch64"

    private let linuxDistros = ["Ubuntu 24.04", "Fedora 41", "Debian 12", "Alpine 3.20", "Arch Linux", "NixOS 24.11"]
    private let macVersions = ["macOS 26 Tahoe", "macOS 15 Sequoia", "macOS 14 Sonoma"]
    private let winVersions = ["Windows 11 ARM", "Windows 10 ARM"]

    var body: some View {
        VStack(spacing: 0) {
            Text("Create Machine").font(.title2.weight(.semibold)).padding()

            Form {
                // OS Selection
                Section("Operating System") {
                    Picker("Type", selection: $os) {
                        Label("Linux", systemImage: "server.rack").tag(MockVM.VMOS.linux)
                        Label("macOS", systemImage: "apple.logo").tag(MockVM.VMOS.macos)
                        Label("Windows", systemImage: "pc").tag(MockVM.VMOS.windows)
                    }
                    .pickerStyle(.segmented)

                    switch os {
                    case .linux:
                        Picker("Distribution", selection: $distro) {
                            ForEach(linuxDistros, id: \.self) { Text($0) }
                        }
                    case .macos:
                        Picker("Version", selection: $distro) {
                            ForEach(macVersions, id: \.self) { Text($0) }
                        }
                        Text("Uses Apple Virtualization.framework. Near-native speed.").font(.caption2).foregroundStyle(.secondary)
                    case .windows:
                        Picker("Version", selection: $distro) {
                            ForEach(winVersions, id: \.self) { Text($0) }
                        }
                        Text("Uses QEMU with HVF acceleration. ~85% native speed for ARM.").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // Name
                Section("Name") {
                    TextField("e.g. dev-ubuntu", text: $name)
                }

                // Resources
                Section("Resources") {
                    Stepper("CPUs: \(Int(cpus))", value: $cpus, in: 1...16)
                    Stepper("Memory: \(Int(memory)) GiB", value: $memory, in: 1...64)
                    Stepper("Disk: \(Int(disk)) GiB", value: $disk, in: 10...500)
                    Picker("Architecture", selection: $arch) {
                        Text("aarch64 (ARM)").tag("aarch64")
                        Text("x86_64 (Intel)").tag("x86_64")
                    }
                    if arch == "x86_64" {
                        Text("⚠️ x86_64 uses QEMU emulation (~30-40% native speed)").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }
            .padding()
            Text("Machine creation is not available in the current daemon contract. This form is preview-only and will not claim success.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(width: 480, height: 520)
    }
}
