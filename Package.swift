// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Backside",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Backside", targets: ["Backside"])],
    targets: [
        .executableTarget(name: "Backside", linkerSettings: [.linkedLibrary("sqlite3")])
    ]
)
