import SwiftUI

// MARK: - Resource Advisor
// Gives intelligent recommendations based on current state

struct ResourceAdvisor: View {
    @EnvironmentObject var appState: AppState

    private var recommendations: [Recommendation] {
        var items: [Recommendation] = []

        guard appState.vmRunning else { return items }

        let cpu = appState.vmCPU
        let memGiB = Double(appState.vmMemory) / 1_073_741_824.0
        let allocText = cpu > 0 ? "\(cpu) CPU, \(String(format: "%.0f", memGiB)) GiB" : "the current allocation"
        let runningContainers = appState.containers.filter { $0.state == "running" }.count

        // Battery-aware (real: ProcessInfo low-power state + real allocation).
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            items.append(Recommendation(
                icon: "battery.25",
                severity: .warning,
                title: "Low Power Mode is on",
                detail: "Colima is allocated \(allocText). Reducing it preserves battery while on the go.",
                action: "Adjust config"
            ))
        }

        // Idle detection (real: running-container count from the backend).
        if runningContainers == 0 {
            items.append(Recommendation(
                icon: "moon.zzz",
                severity: .info,
                title: "No containers running",
                detail: "The VM is idle but holding \(allocText). Stop Colima to free those resources.",
                action: "Stop VM"
            ))
        }

        // Right-sizing hint (real: only when generously provisioned for the host).
        let hostCores = ProcessInfo.processInfo.processorCount
        if cpu > 0 && hostCores > 0 && cpu >= max(4, hostCores / 2) {
            items.append(Recommendation(
                icon: "chart.line.uptrend.xyaxis",
                severity: .info,
                title: "Right-sizing opportunity",
                detail: "Colima holds \(allocText) of this \(hostCores)-core Mac. Lower it in Configuration if workloads are light.",
                action: "Adjust config"
            ))
        }

        return items
    }

    var body: some View {
        if !recommendations.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "sparkles").foregroundStyle(.purple)
                        Text("Smart Recommendations").font(.caption.weight(.medium))
                        Spacer()
                    }
                    ForEach(recommendations) { rec in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: rec.icon)
                                .foregroundStyle(rec.severity.color)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.title).font(.caption.weight(.medium))
                                Text(rec.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(rec.action) {
                                switch rec.action {
                                case "Stop VM": appState.stopVM()
                                default: appState.selectedTab = .configuration
                                }
                            }
                                .font(.caption2)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    struct Recommendation: Identifiable {
        let id = UUID()
        let icon: String
        let severity: Severity
        let title: String
        let detail: String
        let action: String

        enum Severity {
            case info, warning, critical
            var color: Color {
                switch self {
                case .info: return .blue
                case .warning: return .orange
                case .critical: return .red
                }
            }
        }
    }
}
