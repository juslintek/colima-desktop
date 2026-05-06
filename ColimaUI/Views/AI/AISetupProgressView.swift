import SwiftUI

struct AISetupProgressView: View {
    let runner: String
    let onDone: () -> Void
    @State private var currentStep = 0
    @State private var log: [String] = []
    @State private var isComplete = false
    @State private var timer: Timer?

    private var steps: [(name: String, detail: String)] {
        if runner == "ramalama" {
            return [
                ("Checking prerequisites", "Verifying krunkit VM type and GPU access..."),
                ("Installing Ramalama", "Downloading ramalama binary into VM..."),
                ("Configuring GPU passthrough", "Setting up /dev/dri device access..."),
                ("Verifying installation", "Running ramalama --version..."),
            ]
        } else {
            return [
                ("Checking prerequisites", "Verifying Docker runtime is active..."),
                ("Enabling Docker Model Runner", "Configuring docker model plugin..."),
                ("Ready", "Docker Model Runner requires no additional setup."),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Setup — \(runner == "ramalama" ? "Ramalama" : "Docker Model Runner")")
                    .font(.caption.weight(.semibold))
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            // Steps
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 8) {
                    if i < currentStep {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    } else if i == currentStep && !isComplete {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "circle").foregroundStyle(.secondary).font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.name).font(.caption)
                        if i == currentStep {
                            Text(step.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Log output
            if !log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption2, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 60)
                .padding(6)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if isComplete {
                Button("Done") { onDone() }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1)))
        .onAppear { startMockSetup() }
        .onDisappear { timer?.invalidate() }
    }

    private func startMockSetup() {
        let mockLogs = [
            "Checking VM type... krunkit ✓",
            "Checking GPU access... /dev/dri available ✓",
            "Downloading ramalama v0.9.2...",
            "Installing to /home/user/.local/bin/ramalama...",
            "Setting RAMALAMA_CONTAINER_ENGINE=docker",
            "Configuring GPU device passthrough...",
            "ramalama version 0.9.2 ✓",
            "Setup complete!",
        ]
        var logIndex = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            if currentStep < steps.count - 1 {
                if logIndex < mockLogs.count {
                    log.append(mockLogs[logIndex])
                    logIndex += 1
                }
                if logIndex % 2 == 0 { currentStep += 1 }
            } else {
                isComplete = true
                timer?.invalidate()
            }
        }
    }
}
