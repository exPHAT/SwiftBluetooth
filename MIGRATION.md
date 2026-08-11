# Migrating from 1.x to 2.0

The theme of this release is that nothing fails silently. Previously a few methods
crashed the process when used slightly early, and a stream that ended because the
peripheral disconnected looked exactly like one that finished normally. Both are fixed,
and fixing them meant changing signatures.

Where an old name could be kept as a deprecated alias, it was. Those still compile and
tell you what to move to.

## Streams say why they ended

`readValues(for:)` and `scanForPeripherals(...)` return `AsyncThrowingStream` now, so
`for await` becomes `for try await`.

```swift
// Before
for await value in peripheral.readValues(for: characteristic) { … }

// After
for try await value in peripheral.readValues(for: characteristic) { … }
```

They throw when the peripheral disconnects, when a read fails, or when Bluetooth is
switched off mid-scan. They still finish normally in the ordinary cases: notifications
being turned off, `stopScan()`, or a scan timeout elapsing. So `.first` on a scan still
returns `nil` when nothing was found in time — it only throws if scanning became
impossible.

## Nothing traps

Three methods used to call `fatalError` when given a `Characteristic` that hadn't been
discovered yet. They report it instead.

```swift
// These now throw PeripheralError.characteristicNotFound
try peripheral.setNotifyValue(true, for: .someCharacteristic)
try peripheral.writeValue(data, for: .someCharacteristic, type: .withResponse)

// In async code you get the async overloads, which throw the same error
try await peripheral.setNotifyValue(true, for: .someCharacteristic)
try await peripheral.writeValue(data, for: .someCharacteristic, type: .withResponse)

// And this one reports it through the stream
for try await value in peripheral.readValues(for: .someCharacteristic) { … }
```

## `waitUntilReady()` → `wait(for:)`

Waiting is no longer hardcoded to powered-on, and it takes a timeout, so a switched-off
radio can't leave you waiting forever.

```swift
// Before
try await central.waitUntilReady()

// After
try await central.wait(for: .poweredOn)
try await central.wait(for: .poweredOn, timeout: 10)   // gives up with .timedOut
```

`waitUntilReady()` still works, deprecated.

## Completion handlers

`writeValue` reports a `Result` like every other operation, rather than an optional error:

```swift
// Before
peripheral.writeValue(data, for: characteristic, type: .withResponse) { error in
    if let error { … }
}

// After
peripheral.writeValue(data, for: characteristic, type: .withResponse) { result in
    if case .failure(let error) = result { … }
}
```

Cancelling a callback operation now calls the handler with `CancellationError`, where
before it went quiet. If you cancel and don't want to hear back, ignore that case.

## `setNotifyValue` returns nothing

Its `Bool` meant two different things depending on which path answered — the value you
asked for, or the state actually observed. Read `characteristic.isNotifying` instead,
which is the truth either way.

## Renames

| 1.x | 2.0 |
| --- | --- |
| `CentralError` | `CentralManagerError` |
| `peripheral.discovery` | `peripheral.discoveryInfo` (optional, and doesn't trap) |
| `peripheral.acnsAuthorized` | `peripheral.ancsAuthorized` |

All four old names still compile, deprecated.

## Smaller things

- `Peripheral.init(_ cbPeripheral:)` is internal. Constructing one made it the delegate of
  that `CBPeripheral`, quietly taking callbacks away from the instance the manager holds.
  Get peripherals from the manager — by scanning, `retrievePeripherals(withIdentifiers:)`,
  or `retrieveConnectedPeripherals(withServices:)`.
- `CentralManager` and `Peripheral` are `final`.
- Writes without response wait until the peripheral can accept one. CoreBluetooth discards
  them when its buffer is full, so they used to go missing with nothing reported.
- The package requires Swift 6.0 to build. The library itself compiles under the Swift 6
  language mode, so it won't add concurrency warnings to your project.
