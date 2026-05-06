import SwiftUI

struct PullProgressView: View {
    let name: String
    let onCancel: () -> Void
    @State private var layers: [PullLayer] = []
    @State private var totalProgress: Double = 0
    @State private var status: String = "Pulling..."
    @State private var timer: Timer?

    struct PullLayer: Identifiable {
        let id: String
        var size: String
        var downloaded: Double // 0-1
        var status: String // "Downloading", "Extracting", "Done"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)
                Text(name).font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Text(status).font(.caption2).foregroundStyle(.secondary)
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle").font(.caption)
                }.buttonStyle(.borderless)
            }

            // Overall progress
            ProgressView(value: totalProgress)
                .tint(.blue)
            Text("\(Int(totalProgress * 100))% — \(formattedSize)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            // Layer breakdown
            if !layers.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(layers) { layer in
                        HStack(spacing: 6) {
                            Text(layer.id.prefix(12))
                                .font(.system(.caption2, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            ProgressView(value: layer.downloaded)
                                .frame(maxWidth: 100)
                                .tint(layer.status == "Done" ? .green : .blue)
                            Text(layer.size)
                                .font(.caption2.monospacedDigit())
                                .frame(width: 50, alignment: .trailing)
                            Text(layer.status)
                                .font(.caption2)
                                .foregroundStyle(layer.status == "Done" ? .green : .secondary)
                                .frame(width: 80, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { startMockProgress() }
        .onDisappear { timer?.invalidate() }
    }

    private var formattedSize: String {
        let mb = totalProgress * 245
        return String(format: "%.1f / 245.0 MB", mb)
    }

    private func startMockProgress() {
        layers = [
            PullLayer(id: "a1b2c3d4e5f6", size: "32 MB", downloaded: 0, status: "Waiting"),
            PullLayer(id: "b2c3d4e5f6a1", size: "85 MB", downloaded: 0, status: "Waiting"),
            PullLayer(id: "c3d4e5f6a1b2", size: "128 MB", downloaded: 0, status: "Waiting"),
        ]
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation(.linear(duration: 0.3)) {
                for i in layers.indices {
                    if layers[i].downloaded < 1.0 {
                        layers[i].downloaded = min(1.0, layers[i].downloaded + Double.random(in: 0.02...0.08))
                        layers[i].status = layers[i].downloaded >= 1.0 ? "Done" : "Downloading"
                    }
                }
                totalProgress = layers.reduce(0) { $0 + $1.downloaded } / Double(layers.count)
                if totalProgress >= 0.99 {
                    status = "Complete"
                    timer?.invalidate()
                }
            }
        }
    }
}
