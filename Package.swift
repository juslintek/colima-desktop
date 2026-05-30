// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ColimaDesktop",
    platforms: [.macOS(.v14)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: []
)
