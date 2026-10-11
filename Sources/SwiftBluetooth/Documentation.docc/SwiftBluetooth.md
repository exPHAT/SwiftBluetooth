# ``SwiftBluetooth``

Talk to Bluetooth peripherals with async Swift, using the CoreBluetooth names you already know.

## Overview

SwiftBluetooth wraps CoreBluetooth without hiding it. ``CentralManager`` and ``Peripheral``
mirror `CBCentralManager` and `CBPeripheral`, so existing code keeps working, and every
operation gains an `async` form and a completion-handler form alongside the original.

```swift
let central = CentralManager()
try await central.wait(for: .poweredOn)

let peripheral = try await central.scanForPeripherals(withServices: [myService]).first!
try await central.connect(peripheral, timeout: 5)

let service = try await peripheral.discoverServices([myService]).first!
_ = try await peripheral.discoverCharacteristics([.someCharacteristic], for: service)

let value = try await peripheral.readValue(for: .someCharacteristic)

try await central.cancelPeripheralConnection(peripheral)
```

### Three ways to call the same thing

Most operations come in three forms, and you can mix them freely:

- `async`, which throws on failure
- a completion handler taking a `Result`, returning a ``CancellableTask``
- the original CoreBluetooth method, which reports through the delegate

### Failures are always reported

Nothing in this library traps. An operation that can't finish reports why: reads and writes
fail with `CBError.peripheralDisconnected` when the peripheral goes away, a ``Characteristic``
used before it's been discovered gives ``PeripheralError/characteristicNotFound``, and
cancelling gives `CancellationError`.

Streams are the same. ``Peripheral/readValues(for:)-(CBCharacteristic)`` and
``CentralManager/scanForPeripherals(withServices:timeout:options:)`` throw when they end for a
reason you didn't ask for, and finish normally when you did.

### Which queue things arrive on

Delegate callbacks arrive on the queue the ``CentralManager`` was created with — the main
queue unless you passed one — exactly as CoreBluetooth delivers them. Completion handlers and
stream values arrive on an internal serial queue instead, so don't assume they're on the main
thread when updating UI. State restoration is the exception: it's delivered during the
manager's construction, on whichever thread is constructing it.

## Topics

### Connecting

- ``CentralManager``
- ``CentralManagerDelegate``
- ``CentralManagerError``

### Background operation

- <doc:BackgroundOperation>
- ``CentralManagerRestoredState``
- ``CentralManager/connectPersistently(_:options:)``

### Peripherals

- ``Peripheral``
- ``PeripheralDelegate``
- ``PeripheralError``
- ``Characteristic``

### Cancelling work

- ``CancellableTask``
