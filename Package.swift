// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Backside",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Backside", targets: ["Backside"])],
    targets: [.executableTarget(name: "Backside")]
)
