import Foundation

struct DockerEvent {
    let action: String
    let containerName: String
}

struct ContainerStats {
    let cpuPercent: Double
    let memoryUsage: UInt64
    let memoryLimit: UInt64
    let networkRx: UInt64
    let networkTx: UInt64
}

/// Observed image-pull progress, aggregated exclusively from the Docker Engine
/// API `/images/create` stream (jsonmessage events carrying `status`, `id`, and
/// `progressDetail.current`/`progressDetail.total` per layer). Every field is
/// derived from real stream events — there is no synthesized percentage,
/// animated bar, or fake timer. `fraction` is `nil` until real byte totals
/// arrive, so the UI can show an honest indeterminate indicator rather than a
/// fabricated number.
struct ImagePullProgress: Equatable {
    /// Latest human-readable status line from the stream (e.g. "Downloading",
    /// "Extracting", "Pull complete", or the final
    /// "Status: Downloaded newer image for nginx:latest").
    var status: String
    /// Distinct layers observed in a layer phase so far.
    var layerCount: Int
    /// Layers that reached a terminal status ("Download complete", "Pull
    /// complete", or "Already exists").
    var completedLayers: Int
    /// Aggregate OBSERVED bytes downloaded across layers that reported a total.
    var currentBytes: Int64
    /// Aggregate OBSERVED byte total across layers that reported a total.
    var totalBytes: Int64
    /// Observed completion fraction in 0...1, or `nil` when no byte totals have
    /// been reported yet (indeterminate — never a fabricated value).
    var fraction: Double?
    /// True once the stream has ended (success or terminal error).
    var finished: Bool
    /// Non-nil when the stream reported an `error`/`errorDetail` object.
    var errorMessage: String?

    init(
        status: String = "",
        layerCount: Int = 0,
        completedLayers: Int = 0,
        currentBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        fraction: Double? = nil,
        finished: Bool = false,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.layerCount = layerCount
        self.completedLayers = completedLayers
        self.currentBytes = currentBytes
        self.totalBytes = totalBytes
        self.fraction = fraction
        self.finished = finished
        self.errorMessage = errorMessage
    }
}

extension ImagePullProgress {
    /// "3.2 MB / 8.0 MB" once byte totals were observed, else `nil`.
    var byteSummary: String? {
        guard totalBytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: currentBytes)) / \(formatter.string(fromByteCount: totalBytes))"
    }

    /// "42%" once a fraction was observed, else `nil`.
    var percentText: String? {
        guard let fraction else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// One-line human summary built entirely from observed fields (no synthesis).
    var summary: String {
        if let errorMessage { return "Failed: \(errorMessage)" }
        var parts: [String] = []
        if !status.isEmpty { parts.append(status) }
        if let percentText { parts.append(percentText) }
        if let byteSummary { parts.append(byteSummary) }
        if layerCount > 0 { parts.append("\(completedLayers)/\(layerCount) layers") }
        if parts.isEmpty { return finished ? "Complete" : "Pulling…" }
        return parts.joined(separator: " · ")
    }
}
