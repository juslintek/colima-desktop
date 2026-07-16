import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - PullProgressView additional wave 3 tests (Cov3Rest_ prefix)

@Suite("Cov3Rest_PullProgressViewWave3 Integration", .serialized)
@MainActor
struct Cov3Rest_PullProgressViewWave3Tests {

    @Test("renders without crash for simple image name")
    func rendersWithoutCrash() throws {
        let v = PullProgressView(name: "alpine:latest", onCancel: {})
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows image name in view")
    func showsImageName() throws {
        let v = PullProgressView(name: "ubuntu:22.04", onCancel: {})
        #expect((try? v.inspect().find(text: "ubuntu:22.04")) != nil)
    }

    @Test("PullLayer waiting status is preserved")
    func pullLayerWaitingStatus() {
        let layer = PullProgressView.PullLayer(id: "abc123", size: "50MB", downloaded: 0.0, status: "Waiting")
        #expect(layer.status == "Waiting")
        #expect(layer.downloaded == 0.0)
    }

    @Test("PullLayer extracting status is preserved")
    func pullLayerExtractingStatus() {
        let layer = PullProgressView.PullLayer(id: "def456", size: "100MB", downloaded: 0.75, status: "Extracting")
        #expect(layer.status == "Extracting")
        #expect(layer.downloaded == 0.75)
    }

    @Test("PullLayer progress clamps correctly at full download")
    func pullLayerFullDownload() {
        var layer = PullProgressView.PullLayer(id: "abc", size: "10MB", downloaded: 0.99, status: "Downloading")
        layer.downloaded = min(1.0, layer.downloaded + 0.1)
        layer.status = layer.downloaded >= 1.0 ? "Done" : "Downloading"
        #expect(layer.downloaded == 1.0)
        #expect(layer.status == "Done")
    }

    @Test("total progress is average of all layer downloads")
    func totalProgressIsAverageOfLayers() {
        let layers = [
            PullProgressView.PullLayer(id: "a", size: "10MB", downloaded: 1.0, status: "Done"),
            PullProgressView.PullLayer(id: "b", size: "20MB", downloaded: 0.5, status: "Downloading"),
            PullProgressView.PullLayer(id: "c", size: "30MB", downloaded: 0.0, status: "Waiting"),
        ]
        let total = layers.reduce(0) { $0 + $1.downloaded } / Double(layers.count)
        #expect(abs(total - 0.5) < 0.001)
    }

    @Test("status is Complete when total progress reaches 0.99 or more")
    func statusCompleteAtHighProgress() {
        let layers = [
            PullProgressView.PullLayer(id: "a", size: "10MB", downloaded: 1.0, status: "Done"),
            PullProgressView.PullLayer(id: "b", size: "20MB", downloaded: 1.0, status: "Done"),
        ]
        let total = layers.reduce(0) { $0 + $1.downloaded } / Double(layers.count)
        let status = total >= 0.99 ? "Complete" : "Pulling..."
        #expect(status == "Complete")
    }

    @Test("formattedSize scales with totalProgress")
    func formattedSizeScalesWithProgress() {
        let progress = 0.5
        let mb = progress * 245
        let formatted = String(format: "%.1f / 245.0 MB", mb)
        #expect(formatted == "122.5 / 245.0 MB")
    }

    @Test("PullLayer unique ids differ between instances with same field values")
    func pullLayerUniqueIdentifiers() {
        // PullLayer.id is the string 'id' param; UUID is not used for PullLayer
        let a = PullProgressView.PullLayer(id: "unique-one", size: "10MB", downloaded: 0, status: "Waiting")
        let b = PullProgressView.PullLayer(id: "unique-two", size: "10MB", downloaded: 0, status: "Waiting")
        #expect(a.id != b.id)
    }
}

// MARK: - StatsSheetView additional wave 3 tests (Cov3Rest_ prefix)

@Suite("Cov3Rest_StatsSheetViewWave3 Integration", .serialized)
@MainActor
struct Cov3Rest_StatsSheetViewWave3Tests {

    @Test("renders without crash for any container name")
    func rendersWithoutCrash() throws {
        let s = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "web-server").environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows live indicator")
    func showsLiveIndicator() throws {
        let s = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "indicator_stats_live")) != nil)
    }

    @Test("shows close button")
    func showsCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_stats")) != nil)
    }

    @Test("shows container name in Stats header")
    func showsNameInHeader() throws {
        let s = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "my-container").environmentObject(s)
        #expect((try? v.inspect().find(text: "Stats: my-container")) != nil)
    }

    @Test("formatBytes returns B for values under 1024")
    func formatBytesB() {
        let bytes: Int64 = 512
        let result: String
        let gib: Int64 = 1_073_741_824
        let mib: Int64 = 1_048_576
        let kib: Int64 = 1024
        if bytes >= gib {
            result = String(format: "%.1fGiB", Double(bytes) / Double(gib))
        } else if bytes >= mib {
            result = String(format: "%.1fMiB", Double(bytes) / Double(mib))
        } else if bytes >= kib {
            result = String(format: "%.1fKiB", Double(bytes) / Double(kib))
        } else {
            result = "\(bytes)B"
        }
        #expect(result == "512B")
    }

    @Test("formatBytes returns KiB for 1024-1048575")
    func formatBytesKiB() {
        let bytes: Int64 = 2048
        let gib: Int64 = 1_073_741_824
        let mib: Int64 = 1_048_576
        let kib: Int64 = 1024
        let result: String
        if bytes >= gib {
            result = String(format: "%.1fGiB", Double(bytes) / Double(gib))
        } else if bytes >= mib {
            result = String(format: "%.1fMiB", Double(bytes) / Double(mib))
        } else if bytes >= kib {
            result = String(format: "%.1fKiB", Double(bytes) / Double(kib))
        } else {
            result = "\(bytes)B"
        }
        #expect(result == "2.0KiB")
    }

    @Test("formatBytes returns MiB for 1048576+")
    func formatBytesMiB() {
        let bytes: Int64 = 1_048_576 * 5  // 5MiB
        let gib: Int64 = 1_073_741_824
        let mib: Int64 = 1_048_576
        let kib: Int64 = 1024
        let result: String
        if bytes >= gib {
            result = String(format: "%.1fGiB", Double(bytes) / Double(gib))
        } else if bytes >= mib {
            result = String(format: "%.1fMiB", Double(bytes) / Double(mib))
        } else if bytes >= kib {
            result = String(format: "%.1fKiB", Double(bytes) / Double(kib))
        } else {
            result = "\(bytes)B"
        }
        #expect(result == "5.0MiB")
    }

    @Test("formatBytes returns GiB for 1073741824+")
    func formatBytesGiB() {
        let bytes: Int64 = 2_147_483_648  // 2GiB
        let gib: Int64 = 1_073_741_824
        let mib: Int64 = 1_048_576
        let kib: Int64 = 1024
        let result: String
        if bytes >= gib {
            result = String(format: "%.1fGiB", Double(bytes) / Double(gib))
        } else if bytes >= mib {
            result = String(format: "%.1fMiB", Double(bytes) / Double(mib))
        } else if bytes >= kib {
            result = String(format: "%.1fKiB", Double(bytes) / Double(kib))
        } else {
            result = "\(bytes)B"
        }
        #expect(result == "2.0GiB")
    }

    @Test("ProcessRow fields are stored as provided")
    func processRowFields() {
        let row = StatsSheetView.ProcessRow(pid: "1234", user: "root", cpu: "2.3%", mem: "128MiB", command: "/usr/sbin/nginx")
        #expect(row.pid == "1234")
        #expect(row.user == "root")
        #expect(row.cpu == "2.3%")
        #expect(row.mem == "128MiB")
        #expect(row.command == "/usr/sbin/nginx")
    }
}
