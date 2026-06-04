import SwiftUI

/// Shown when Colima is not installed on the host. Offers a one-click Homebrew install.
struct InstallColimaView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
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
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
