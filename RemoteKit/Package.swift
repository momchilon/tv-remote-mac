// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RemoteKit", targets: ["RemoteKit"]),
        .executable(name: "RemoteCheck", targets: ["RemoteCheck"])
    ],
    targets: [
        .target(name: "RemoteKit"),
        .executableTarget(name: "RemoteCheck", dependencies: ["RemoteKit"]),
        .testTarget(name: "RemoteKitTests", dependencies: ["RemoteKit", "RemoteCheck"], resources: [.copy("Fixtures")])
    ]
)
