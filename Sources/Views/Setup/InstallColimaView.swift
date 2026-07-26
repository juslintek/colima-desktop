import SwiftUI

/// Shown when Colima is not installed on the host. Offers a one-click Homebrew
/// install and a live dependency checklist for every tool Colima Desktop tracks
/// (Requirement 10 / DependencyManager): `colima`, `lima`, `qemu`, `krunkit`,
/// `docker-cli`, and `kubectl`. The checklist reflects the REAL host state and
/// offers an install path for anything missing or outdated.
struct InstallColimaView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Colima is not installed")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("text_colima_not_installed")
                Text("Colima Desktop needs the Colima runtime. Install it with Homebrew — this also installs the docker CLI.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)

                if appState.isInstallingColima {
                    ProgressView("Installing Colima… this can take a few minutes")
                        .accessibilityIdentifier("progress_installing_colima")
                } else {
                    Button {
                        appState.installColima()
                    } label: {
                        Label("Install Colima", systemImage: "arrow.down.circle.fill")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("btn_install_colima")

                    Text("Requires Homebrew. If you don't have it, install from brew.sh first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                dependencyChecklist
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .task { await appState.checkDependencies() }
    }

    // MARK: - Dependency checklist

    private var dependencyChecklist: some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(appState.dependencyStatuses) { status in
                    DependencyRow(
                        status: status,
                        isInstalling: appState.installingTools.contains(status.tool),
                        install: { appState.installDependency(status.tool) }
                    )
                    if status.id != appState.dependencyStatuses.last?.id {
                        Divider()
                    }
                }
                if appState.dependencyStatuses.isEmpty {
                    Text("Checking dependencies…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
        } label: {
            HStack {
                Text("Dependencies")
                Spacer()
                Button {
                    Task { await appState.checkDependencies() }
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .accessibilityIdentifier("btn_recheck_dependencies")
            }
        }
        .frame(maxWidth: 480)
        .accessibilityIdentifier("group_dependency_checklist")
    }
}

/// One row of the dependency checklist: state icon, name + version, remediation,
/// and an install button when the tool is missing or outdated.
private struct DependencyRow: View {
    let status: DependencyStatus
    let isInstalling: Bool
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .accessibilityIdentifier("icon_dep_\(status.tool.rawValue)_\(status.state.rawValue)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(status.tool.displayName).fontWeight(.medium)
                    if let version = status.detectedVersion {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                    }
                    if status.tool.isRequired {
                        Text("required").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(status.remediation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !status.isInstalled {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("progress_install_\(status.tool.rawValue)")
                } else {
                    Button(status.state == .outdated ? "Upgrade" : "Install", action: install)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("btn_install_dep_\(status.tool.rawValue)")
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("row_dependency_\(status.tool.rawValue)")
    }

    private var iconName: String {
        switch status.state {
        case .installed: return "checkmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .outdated: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch status.state {
        case .installed: return .green
        case .missing: return status.tool.isRequired ? .red : .secondary
        case .outdated: return .orange
        }
    }
}
