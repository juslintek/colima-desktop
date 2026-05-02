import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(appState.vmRunning ? .green : .red).frame(width: 10, height: 10)
                Text(appState.vmRunning ? "Colima Running" : "Colima Stopped")
                    .fontWeight(.medium)
                    .accessibilityIdentifier("menubar_status_text")
            }

            Divider()

            Button("Start") { appState.startVM() }
                .accessibilityIdentifier("menubar_btn_start")
                .disabled(appState.vmRunning)
            Button("Stop") { appState.stopVM() }
                .accessibilityIdentifier("menubar_btn_stop")
                .disabled(!appState.vmRunning)
            Button("Restart") { appState.restartVM() }
                .accessibilityIdentifier("menubar_btn_restart")
                .disabled(!appState.vmRunning)

            Divider()

            Text("Profile: \(appState.activeProfile)").font(.caption).foregroundStyle(.secondary)
            Text("Runtime: docker").font(.caption).foregroundStyle(.secondary)
            Text("Containers: \(appState.containers.count)").font(.caption).foregroundStyle(.secondary)

            Divider()

            Button("Open ColimaUI") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }.accessibilityIdentifier("menubar_btn_open")

            Button("Quit") {
                NSApp.terminate(nil)
            }.accessibilityIdentifier("menubar_btn_quit")
        }
        .padding()
        .frame(width: 220)
    }
}
