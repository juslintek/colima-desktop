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
