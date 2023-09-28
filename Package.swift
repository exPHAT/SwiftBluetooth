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
    dependencies: [
        .package(url: "https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock.git", branch: "main")],
    targets: [
        .target(name: "SwiftBluetooth"),
        .target(name: "SwiftBluetoothMock",
                dependencies: [.product(name: "CoreBluetoothMock", package: "IOS-CoreBluetooth-Mock")],
                exclude: ["SwiftBluetooth/CentralManager/CBCentralManagerFactory.swift"]),
        .testTarget(name: "SwiftBluetoothTests",
                    dependencies: ["SwiftBluetoothMock"])]
)
