import SwiftUI

// MARK: - Command Item

struct CommandItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let category: String
    let action: () -> Void
}

// MARK: - Command Palette

struct CommandPalette: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var commands: [CommandItem] {
        var items: [CommandItem] = []

        // Navigation
        items.append(CommandItem(title: "Go to Containers", subtitle: "View all containers", icon: "shippingbox", category: "Navigation") { appState.selectedTab = .containers })
        items.append(CommandItem(title: "Go to Images", subtitle: "View all images", icon: "photo.stack", category: "Navigation") { appState.selectedTab = .images })
        items.append(CommandItem(title: "Go to Volumes", subtitle: "View all volumes", icon: "externaldrive", category: "Navigation") { appState.selectedTab = .volumes })
        items.append(CommandItem(title: "Go to Activity Monitor", subtitle: "CPU, memory, processes", icon: "chart.xyaxis.line", category: "Navigation") { appState.selectedTab = .monitoring })
        items.append(CommandItem(title: "Go to Configuration", subtitle: "VM and runtime settings", icon: "gearshape", category: "Navigation") { appState.selectedTab = .configuration })
        items.append(CommandItem(title: "Go to Kubernetes", subtitle: "Pods and services", icon: "helm", category: "Navigation") { appState.selectedTab = .kubernetes })

        // Actions
        items.append(CommandItem(title: "Start Colima", subtitle: "Start the VM", icon: "play.fill", category: "Actions") { appState.startVM() })
        items.append(CommandItem(title: "Stop Colima", subtitle: "Stop the VM", icon: "stop.fill", category: "Actions") { appState.stopVM() })
        items.append(CommandItem(title: "Restart Colima", subtitle: "Restart the VM", icon: "arrow.clockwise", category: "Actions") { appState.restartVM() })
        items.append(CommandItem(title: "Create Container", subtitle: "Run a new container", icon: "plus.circle", category: "Actions") { appState.activeSheet = .createContainer })
        items.append(CommandItem(title: "Prune System", subtitle: "Remove unused resources", icon: "trash", category: "Actions") { appState.pruneSystem() })

        // Containers (dynamic)
        for c in appState.containers {
            items.append(CommandItem(title: c.name, subtitle: "\(c.image) — \(c.state)", icon: "shippingbox", category: "Containers") {
                appState.selectedTab = .containers
                appState.selectedContainerName = c.name
            })
        }

        // Profiles
        for p in appState.profiles {
            items.append(CommandItem(title: "Switch to \(p.name)", subtitle: "\(p.runtime) — \(p.status)", icon: "person.crop.rectangle", category: "Profiles") {
                appState.switchProfile(name: p.name)
            })
        }

        return items
    }

    private var filteredCommands: [CommandItem] {
        guard !query.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedCommands: [(String, [CommandItem])] {
        Dictionary(grouping: filteredCommands, by: \.category)
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type a command or search...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit { executeSelected() }
                    .accessibilityIdentifier("field_command_search")

                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }

                Text("esc").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.secondary.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(12)

            Divider()

            // Results
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groupedCommands.enumerated()), id: \.offset) { _, group in
                        Text(group.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

                        ForEach(group.1) { item in
                            commandRow(item)
                        }
                    }

                    if filteredCommands.isEmpty {
                        Text("No results for \"\(query)\"")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
        .onKeyPress(.downArrow) { selectedIndex = min(filteredCommands.count - 1, selectedIndex + 1); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
        .accessibilityIdentifier("sheet_command_palette")
    }

    private func commandRow(_ item: CommandItem) -> some View {
        let isSelected = filteredCommands.firstIndex(where: { $0.id == item.id }) == selectedIndex
        return Button {
            item.action()
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .white : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.body)
                    Text(item.subtitle).font(.caption).foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }
                Spacer()
                if isSelected {
                    Text("↵").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cmd_\(item.title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }

    private func executeSelected() {
        guard selectedIndex < filteredCommands.count else { return }
        filteredCommands[selectedIndex].action()
        isPresented = false
    }
}
