// swift-tools-version: 6.0

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
        .package(url: "https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock.git", "0.17.0"..<"0.18.0")],
    targets: [
        .target(name: "SwiftBluetooth",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        // The same sources again, against CoreBluetoothMock. They're already checked under
        // Swift 6 by the target above, and the mock's types carry none of the Sendable
        // annotations CoreBluetooth has, so checking this copy only reports on the mock.
        .target(name: "SwiftBluetoothMock",
                dependencies: [.product(name: "CoreBluetoothMock", package: "IOS-CoreBluetooth-Mock")],
                exclude: ["SwiftBluetooth/CentralManager/CBCentralManagerFactory.swift"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwiftBluetoothTests",
                    dependencies: ["SwiftBluetoothMock"],
                    swiftSettings: [.swiftLanguageMode(.v5)])]
)
