import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private var runningCount: Int {
        appState.containers.filter { $0.state == "running" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with VM status
            HStack {
                Circle().fill(appState.vmRunning ? .green : .red).frame(width: 8, height: 8)
                Text("Colima").font(.headline)
                Spacer()
                Text(appState.vmRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menubar_vm_status")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Quick metrics row
            HStack(spacing: 16) {
                metricPill(icon: "shippingbox", value: "\(runningCount)", label: "containers", id: "menubar_metric_containers")
                metricPill(icon: "photo.stack", value: "\(appState.images.count)", label: "images", id: "menubar_metric_images")
                metricPill(icon: "externaldrive", value: "\(appState.volumes.count)", label: "volumes", id: "menubar_metric_volumes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Container list
            if !appState.containers.isEmpty {
                Text("Containers")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                ForEach(appState.containers.prefix(5)) { c in
                    MenuBarContainerRow(container: c)
                }

                if appState.containers.count > 5 {
                    Text("\(appState.containers.count - 5) more...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button("Open Colima Desktop") {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    // Show all windows
                    for window in NSApp.windows where window.canBecomeMain || window.title.contains("Colima") {
                        window.setIsVisible(true)
                        window.deminiaturize(nil)
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("btn_menubar_open")

                Spacer()

                if appState.vmRunning {
                    Button("Stop") { appState.stopVM() }
                        .controlSize(.small)
                        .accessibilityIdentifier("btn_menubar_stop_vm")
                } else {
                    Button("Start") { appState.startVM() }
                        .controlSize(.small)
                        .accessibilityIdentifier("btn_menubar_start_vm")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    private func metricPill(icon: String, value: String, label: String, id: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Container Row

struct MenuBarContainerRow: View {
    let container: MockContainer
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(container.name)
                .font(.callout)
                .lineLimit(1)
            Spacer()

            if isHovered {
                if container.state == "running" {
                    Button { appState.stopContainer(name: container.name) } label: {
                        Image(systemName: "stop.fill").font(.caption2)
                    }.buttonStyle(.borderless)
                    Button { appState.restartContainer(name: container.name) } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }.buttonStyle(.borderless)
                } else {
                    Button { appState.startContainer(name: container.name) } label: {
                        Image(systemName: "play.fill").font(.caption2)
                    }.buttonStyle(.borderless)
                }
            } else {
                Text(container.state)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovered ? Color.accentColor.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovered = $0 }
    }

    private var statusColor: Color {
        switch container.state {
        case "running": return .green
        case "paused": return .yellow
        default: return .red
        }
    }
}
