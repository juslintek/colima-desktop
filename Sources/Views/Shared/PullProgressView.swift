import SwiftUI

struct PullProgressView: View {
    let name: String
    /// OBSERVED progress parsed from the Docker Engine pull stream. When byte
    /// totals have been reported a determinate bar is shown; before then an
    /// honest indeterminate indicator is used (never a fabricated percentage).
    var progress: ImagePullProgress? = nil
    var status: String = "Pulling..."
    let onCancel: () -> Void

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
                if let percent = progress?.percentText {
                    Text(percent)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("label_pull_percent")
                }
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle").font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("btn_cancel_pull")
            }

            // Progress is derived entirely from observed Docker Engine
            // `/images/create` stream events (per-layer progressDetail
            // current/total). A determinate bar is shown once real byte totals
            // arrive; before that the indeterminate indicator is honest rather
            // than a fabricated percentage.
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
                    .tint(.blue)
                    .accessibilityIdentifier("progress_pull_determinate")
            } else {
                ProgressView()
                    .tint(.blue)
                    .accessibilityIdentifier("progress_pull_indeterminate")
            }

            Text(detailLine)
                .font(.caption2)
                .foregroundStyle(progress?.errorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(2)
                .accessibilityIdentifier("label_pull_status")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Prefer the observed stream summary; fall back to the caller-supplied
    /// status string before the first event arrives.
    private var detailLine: String {
        if let progress {
            let summary = progress.summary
            if !summary.isEmpty { return summary }
        }
        return status
    }
}
