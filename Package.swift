// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchRemote",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NotchUI", targets: ["NotchUI"]),
        .executable(name: "NotchRemote", targets: ["NotchRemote"])
    ],
    dependencies: [.package(path: "RemoteKit")],
    targets: [
        .target(name: "NotchUI", dependencies: [.product(name: "RemoteKit", package: "RemoteKit")]),
        .executableTarget(name: "NotchRemote", dependencies: ["NotchUI", .product(name: "RemoteKit", package: "RemoteKit")]),
        .testTarget(name: "NotchUITests", dependencies: ["NotchUI"])
    ]
)
