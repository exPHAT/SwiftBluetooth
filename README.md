# SwiftBluetooth

> CoreBluetooth API's for modern Swift

Easily interface with Bluetooth peripherals in new or existing projects through convienient, modern, Swifty API's.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FexPHAT%2FSwiftBluetooth%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/exPHAT/SwiftBluetooth)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FexPHAT%2FSwiftBluetooth%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/exPHAT/SwiftBluetooth)


## Features

- [x] Modern, async API for reading/writing characteristic values
- [x] Method and delegate parity with existing `CoreBluetooth` API's
- [x] Fallback callback-based completion handlers for new async methods
- [x] Subscribe to peripheral/characteristic updates through `AsyncStream`
- [x] Async peripheral discovery
- [x] Thread safe
- [x] Staticly-typed characteristic definitions
- [ ] SwiftUI API

## Usage 

[API Documentation.](https://swiftpackageindex.com/exPHAT/SwiftBluetooth/1.0.0/documentation/)

The following example connects to the first perpheral it sees and reads the value of a known characteristic (in just 8 lines!).

```swift
let central = CentralManager()
await central.waitUntilReady()

guard let device = await central.scanForPeripherals(withServices: [myService]).first else { return }
await central.connect(device)
defer { central.cancelPeripheralConnection(device) }

guard let service = await device.discoverServices([myService]).first(where: { $0.uuid == myService }) else { return }
let _ = await device.discoverCharacteristics([.someCharacteristic], for: service)

print("Got value:", await device.readValue(for: .someCharacteristic))
```

## Install


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

#### Xcode

Add `https://github.com/exPHAT/SwiftBluetooth.git` in the ["Swift Package Manager" tab.](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)

