![SwiftBluetooth](.github/assets/logo.jpg)

Easily interface with Bluetooth peripherals in new or existing projects through modern async Swift API's.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FexPHAT%2FSwiftBluetooth%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/exPHAT/SwiftBluetooth)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FexPHAT%2FSwiftBluetooth%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/exPHAT/SwiftBluetooth)


## Features

- [x] Parity with existing `CoreBluetooth` APIs for easy, incremental migration of existing projects
- [x] Modern, async-await API for discovery, connection, read/write, and more
- [x] Alternate callback-based API for codebases not using Swift Concurrency
- [x] Subscribe to peripheral discoveries, value updates, and more through `AsyncStream`
- [x] Easy await-ing of `CentralManager` state
- [x] Staticly typed characteristics
- [x] Thread safe, and checked under the Swift 6 language mode
- [x] Zero inherited dependencies
- [x] Tested with included `SwiftBluetoothMock` library

## Examples

[API Documentation.](https://swiftpackageindex.com/exPHAT/SwiftBluetooth/master/documentation/)

#### Complete example

Async API's make the entire Bluetooth lifecycle much simpler, using method names you're already familiar with from CoreBluetooth.

```swift
import SwiftBluetooth

let central = CentralManager()
try await central.wait(for: .poweredOn)

// Find and connect to the first available peripheral
let peripheral = try await central.scanForPeripherals(withServices: [myService]).first!
try await central.connect(peripheral, timeout: 5)

// Discover services and characteristics
let service = try await peripheral.discoverServices([myService]).first!
let _ = try await peripheral.discoverCharacteristics([.someCharacteristic], for: service)

// Read data directly from your characteristic
let value = try await peripheral.readValue(for: .someCharacteristic)

try await central.cancelPeripheralConnection(peripheral)
```

#### Callbacks

Stock CoreBluetooth methods now also have an additional overload that takes a completionHandler for projects not using Swift Concurrency.

```swift
central.connect(peripheral) { result in
  switch result {
  case .failure(let error):
    // Issue connecting
    print("Could not connect:", error)
  case .success(let peripheral):
    // Connected!
    print("Connected to:", peripheral.name ?? "Unknown")
  }
}
```
> Methods often now have 3 overloads. One marked `async`, one with a `completionHandler`, and the original CoreBluetooth verision. Meaning you can choose whichever is most convienient at the time.

#### Stream discovered peripherals

Some operations (like scanning) conform to `AsyncStream`, meaning you can use for-await-in loops to iterate over new items.

```swift
for try await peripheral in await central.scanForPeripherals() {
  print("Discovered:", peripheral.name ?? "Unknown")
}
```
> **Note**
Streams report failures rather than ending quietly, so a scan that stops because Bluetooth was switched off throws. Asking a scan to stop, or its timeout elapsing, finishes it normally.

#### Defining characteristics

Characteristics can be staticly defined on the stock `Characteristic` type, which removes the burden of keeping track of `CBCharacteristic` instances around your app.

```swift
extension Characteristic {
  static let someCharacteristic = Self("00000000-0000-0000-0000-000000000000")
}

// Use those characteristics later on your peripheral
try await myPeripheral.readValue(for: .someCharacteristic)
```
> **Note**
Characteristics have to be discovered before they can be used. Using one that hasn't been throws `PeripheralError.characteristicNotFound`.


#### Watching with callbacks

Peristent tasks return a `CancellableTask` that needs to be cancelled when you're done.

```swift
let task = central.scanForPeripherals { peripheral in
  print("Discovered:", peripheral.name ?? "Unknown")
}

// At some point later, cancel the task to stop scanning
task.cancel()
```
> **Note**
Only one scan can run at a time. Calling `central.stopScan()`, or starting another scan, will cancel any peripheral scanning tasks and finish any scanning streams.

#### Migrate existing projects

Existing projects that already use `CoreBluetooth` can immediately get started by typealiasing the stock types. Afterwards, you can adopt async API's at your own pace.

```swift
import CoreBluetooth
import SwiftBluetooth // Add this

// Override existing CoreBluetooth classes to use SwiftBluetooth
typealias CBCentralManager         = SwiftBluetooth.CentralManager
typealias CBCentralManagerDelegate = SwiftBluetooth.CentralManagerDelegate
typealias CBPeripheral             = SwiftBluetooth.Peripheral
typealias CBPeripheralDelegate     = SwiftBluetooth.PeripheralDelegate

// Your existing code should continue to work as normal.
// But now you have access to all the new API's!
```

## Upgrading from 1.x

See [MIGRATION.md](MIGRATION.md). In short: nothing traps any more, streams report why they
ended, and `waitUntilReady()` became `wait(for:)`.


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
    .package(url: "https://github.com/exPHAT/SwiftBluetooth.git", from: "2.0.0"),
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
