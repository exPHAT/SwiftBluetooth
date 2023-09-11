# SwiftBluetooth

> CoreBluetooth API's for modern Swift

Easily interface with Bluetooth peripherals in new or existing projects through convienient, modern, Swifty API's.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FexPHAT%2FSwiftBluetooth%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/exPHAT/SwiftBluetooth)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FexPHAT%2FSwiftBluetooth%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/exPHAT/SwiftBluetooth)


## Features

- [x] Parity with existing `CoreBluetooth` APIs for easy, incremental migration of existing projects
- [x] Modern, async-await API for peripheral discovery, connection, read/write, etc
- [x] Alternate callback-based API for codebases not using Swift Cocurrency
- [x] Subscribe to peripheral discoveries, value updates, and more through `AsyncStream`
- [x] Easy await-ing of `CentralManager` state
- [x] Static-typing for characteristics
- [x] Thread safe
- [x] Zero dependencies
- [ ] SwiftUI API

## Examples

[API Documentation.](https://swiftpackageindex.com/exPHAT/SwiftBluetooth/1.0.0/documentation/)


#### Migrate existing CoreBluetooth project

```swift
import CoreBluetooth
import SwiftBluetooth // Add this

// Override existing CoreBluetooth classes to use SwiftBluetooth
typealias CBCentralManager = SwiftBluetooth.CentralManager
typealias CBCentralManagerDelegate = SwiftBluetooth.CentralManagerDelegate

typealias CBPeripheral = SwiftBluetooth.Peripheral
typealias CBPeripheralDelegate = SwiftBluetooth.PeripheralDelegate

// Your existing codebase should work as normal, while letting you use all of SwiftBluetooth's new API's!
```

#### Stream discovered peripherals

```swift
let central = CentralManager()
await central.waitUntilReady()

for await peripheral in central.scanForPeripherals() {
  print("Discovered peripheral:", peripheral.name ?? "Unknown")
}
```

#### Define characteristics

```swift
// Define your characteristic UUID's as static members of the `Characteristic` type
extension Characteristic {
  static let someCharacteristic = Self("00000000-0000-0000-0000-000000000000")
}

// Use those characteristics later on your peripheral
await myPeripheral.readValue(for: .someCharacteristic)
```

#### Discover, connect, and read characteristic

```swift
let central = CentralManager()
await central.waitUntilReady()

// Find and connect to the first peripheral
guard let peripheral = await central.scanForPeripherals(withServices: [myService]).first else { return }
await central.connect(peripheral)
defer { central.cancelPeripheralConnection(peripheral) }

// Discover services and characteristics
guard let service = await peripheral.discoverServices([myService]).first(where: { $0.uuid == myService }) else { return }
let _ = await peripheral.discoverCharacteristics([.someCharacteristic], for: service)

// Read characteristic value!
print("Got value:", await peripheral.readValue(for: .someCharacteristic))
```


## Install

#### Xcode

Add `https://github.com/exPHAT/SwiftBluetooth.git` in the ["Swift Package Manager" tab.](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)


#### Swift Package Manager

Add SwiftBluetooth as a dependency in your `Package.swift` file:

```swift
let package = Package(
  ...
  dependencies: [
    // Add the package to your dependencies
    .package(url: "https://github.com/exPHAT/SwiftBluetooth.git", branch: "master"),
  ],
  ...
  targets: [
    // Add SwiftBluetooth as a dependency on any target you want to use it in
    .target(name: "MyTarget",
            dependencies: [.byName(name: "SwiftBluetooth")])
  ]
  ...
)
```
