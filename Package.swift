// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "SwiftBluetooth",
    platforms: [.iOS(.v14),
                .macOS(.v10_15),
                .tvOS(.v15),
                .watchOS(.v7)],
    products: [
        .library(name: "SwiftBluetooth", targets: ["SwiftBluetooth"])],
    targets: [
        .target(name: "SwiftBluetooth", dependencies: []),
        .testTarget(name: "SwiftBluetoothTests", dependencies: ["SwiftBluetooth"])]
)
