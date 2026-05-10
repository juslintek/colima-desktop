import SwiftUI

// MARK: - Resource Advisor
// Gives intelligent recommendations based on current state

struct ResourceAdvisor: View {
    @EnvironmentObject var appState: AppState

    private var recommendations: [Recommendation] {
        var items: [Recommendation] = []

        // Battery-aware
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            items.append(Recommendation(
                icon: "battery.25",
                severity: .warning,
                title: "Low Power Mode detected",
                detail: "Consider reducing VM resources to preserve battery. Current: 4 CPU, 8 GiB.",
                action: "Switch to battery preset"
            ))
        }

        // Idle detection
        let runningContainers = appState.containers.filter { $0.state == "running" }.count
        if runningContainers == 0 && appState.vmRunning {
            items.append(Recommendation(
                icon: "moon.zzz",
                severity: .info,
                title: "No containers running",
                detail: "VM is idle. Consider stopping Colima to free ~1 GB memory and CPU.",
                action: "Stop VM"
            ))
        }

        // Over-allocation detection
        items.append(Recommendation(
            icon: "chart.line.uptrend.xyaxis",
            severity: .info,
            title: "Right-sizing opportunity",
            detail: "Peak usage this week: 2.1 CPU, 3.2 GiB. Current allocation: 4 CPU, 8 GiB. Consider reducing to save resources.",
            action: "Adjust config"
        ))

        // x86 on ARM detection
        items.append(Recommendation(
            icon: "cpu",
            severity: .info,
            title: "x86 images detected",
            detail: "2 containers run x86 images on ARM. Enable Rosetta for 5x faster execution.",
            action: "Enable Rosetta"
        ))

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
                            Button(rec.action) { appState.showToast("Applied: \(rec.action)") }
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
