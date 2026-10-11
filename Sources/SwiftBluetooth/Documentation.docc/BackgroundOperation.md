# Background Operation

Reconnect to peripherals while your app is suspended — or after iOS has terminated it.

## Overview

iOS keeps CoreBluetooth work alive on your app's behalf. A connection request with no
timeout stays with the system while your app is suspended, and — with state restoration
opted in — even after it is terminated: when the peripheral becomes available, iOS
relaunches the app in the background, hands the manager back what it was doing, and
delivers the outcome.

Two things are required:

1. The `bluetooth-central` entry in your Info.plist's `UIBackgroundModes`.
2. A stable ``CentralManager/restoreIdentifier``, the same string on every launch:

```swift
let central = CentralManager(delegate: self, restoreIdentifier: "my-app-central")
```

State restoration exists on iOS, iPadOS and tvOS. Elsewhere the identifier is ignored.

## Build the manager eagerly

A manager that doesn't exist can't be restored. iOS delivers
``CentralManagerDelegate/centralManager(_:willRestore:)`` during the manager's
construction, and a background relaunch renders no UI — so a manager created lazily by a
view never comes back. Create it at launch, unconditionally on any launch where Bluetooth
permission has already been granted.

Note that creating a `CBCentralManager` is also what triggers the Bluetooth permission
prompt, so gate eager construction on `CBCentralManager.authorization == .allowedAlways`
if your app defers that prompt.

## What restoration delivers

``CentralManagerDelegate/centralManager(_:willRestore:)`` is the first callback there is:
it arrives before ``CentralManagerDelegate/centralManagerDidUpdateState(_:)``, so the
manager usually hasn't reported `.poweredOn` yet. It only reaches a delegate passed to
``CentralManager/init(delegate:restoreIdentifier:queue:options:)``; anything attached
later reads ``CentralManager/restoredState``, which is set before the delegate call and
never changes.

The restored peripherals are already registered with the manager — the same objects
every later lookup returns. Their quirks:

- **They may already be connected.** Restoration is not a connection event: no
  `didConnect` is delivered for a peripheral that came back connected. Check
  ``Peripheral/state``. ``CentralManager/connectedPeripherals`` includes them.
- **They have no ``Peripheral/discoveryInfo``.** They were never advertised to this
  process. Identify them by ``Peripheral/identifier``, or by ``Peripheral/services``,
  which CoreBluetooth repopulates along with any characteristics discovered in the
  previous launch — those resolve through ``Peripheral/characteristic(for:)`` without
  re-running discovery.
- **Notifications the previous launch enabled are still on**, and are adopted as
  external subscriptions so a value stream ending in this launch won't switch them off.

A restored *scan* belongs to the previous launch: ``CentralManager/isScanning`` reports
`true` and discoveries reach the delegate, but no stream or callback created in this
launch is attached to it. Stop it, or start your own scan, which replaces it.

## Pending connects, and re-arming them

``CentralManager/connectPersistently(_:options:)`` places the request that makes all of
this go: no timeout, not tied to a task, consumed by whichever outcome arrives first.
Three things silently destroy a pending request, so re-arm:

- on every `.poweredOn` — a radio power-cycle discards every pending request without
  reporting anything, and a fresh launch starts with none;
- from ``CentralManagerDelegate/centralManager(_:didFailToConnect:error:)`` — a failure
  consumes the request;
- from ``CentralManagerDelegate/centralManager(_:didDisconnectPeripheral:error:)`` — so
  does a disconnection.

Re-arming when a request is already in place is harmless. The `async`
``CentralManager/connect(_:timeout:options:)`` is the wrong tool here: cancelling its
task tears the pending request down, by design.

## What iOS will not do

iOS does not relaunch an app the user terminated from the app switcher — the pending
requests stay dead until the user opens the app again. And a background relaunch buys
only a few seconds of runtime per Bluetooth event; do long work incrementally.
