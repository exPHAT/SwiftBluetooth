import Foundation
@preconcurrency import CoreBluetooth

internal final class CentralManagerDelegateWrapper: NSObject, CBCentralManagerDelegate {
    private let lock = NSLock()
    private weak var _parent: CentralManager?

    // CoreBluetooth delivers `willRestoreState` while the manager that owns this wrapper is
    // still being built — CoreBluetoothMock does it synchronously inside `CBCentralManager.init`.
    // It's the one callback that can't be missed, so it waits here until there's a parent to
    // give it to.
    private var pendingRestoredState: [String: Any]?

    private var parent: CentralManager? {
        lock.lock()
        defer { lock.unlock() }

        return _parent
    }

    /// Wires this wrapper to the manager that owns it, delivering anything that arrived
    /// during construction.
    internal func attach(to parent: CentralManager) {
        lock.lock()
        _parent = parent
        let pending = pendingRestoredState
        pendingRestoredState = nil
        lock.unlock()

        if let pending = pending {
            deliverRestoredState(pending, to: parent)
        }
    }

    // MARK: - CBCentralManagerDelegate conformance
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let parent = self.parent else { return }

        parent.delegate?.centralManagerDidUpdateState(parent)

        // Read from the manager we were handed rather than the parent's reference to it,
        // which is still being published when the first state callback arrives
        let state = central.state

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.stateUpdated(state))

            // Losing the radio invalidates every peripheral without CoreBluetooth
            // reporting a disconnection for any of them
            switch state {
            case .poweredOff, .resetting, .unauthorized, .unsupported:
                parent.invalidatePeripherals(with: CBError(.peripheralDisconnected))
            default:
                break
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.markConnected(peripheral)
        parent.delegate?.centralManager(parent, didConnect: peripheral)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.connected(peripheral))
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let parent = parent,
              // Nothing to report for a peripheral we aren't tracking, and picking one up
              // here would only build a wrapper for something that has already gone away
              let peripheral = parent.existingPeripheral(peripheral) else { return }

        parent.markDisconnected(peripheral)
        parent.delegate?.centralManager(parent, didDisconnectPeripheral: peripheral, error: error)

        // The peripheral instance is deliberately kept so a device that reconnects is
        // represented by the same object. Callers who no longer need it can drop it
        // with `CentralManager.forgetPeripheral(_:)`.

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.disconnected(peripheral, error))
            peripheral.eventSubscriptions.receive(.didDisconnect(error))
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let parent = parent,
              let peripheral = parent.existingPeripheral(peripheral) else { return }

        parent.delegate?.centralManager(parent, didFailToConnect: peripheral, error: error)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.failToConnect(peripheral, error))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)
        peripheral.updateDiscovery(.init(rssi: RSSI, advertisementData: advertisementData))

        parent.delegate?.centralManager(
            parent,
            didDiscover: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI
        )

        let transfer = UncheckedTransfer(advertisementData)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.discovered(peripheral, transfer.value, RSSI))
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        lock.lock()
        guard let parent = _parent else {
            // Arrived while the manager is still being built; `attach(to:)` delivers it.
            pendingRestoredState = dict
            lock.unlock()
            return
        }
        lock.unlock()

        deliverRestoredState(dict, to: parent)
    }

    private func deliverRestoredState(_ dict: [String: Any], to parent: CentralManager) {
        // Registering each one repoints any wrapper we already hold at the instance the system
        // just handed back, seeds its already-discovered characteristics, and picks up the ones
        // that came back still connected — CoreBluetooth delivers no `didConnect` for those.
        let peripherals = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [])
            .map(parent.peripheral(_:))

        let state = CentralManagerRestoredState(
            peripherals: peripherals,
            scanServices: dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID],
            scanOptions: dict[CBCentralManagerRestoredStateScanOptionsKey] as? [String: Any],
            dictionary: dict
        )

        // Stored before the delegate hears about it, so a delegate that reads
        // `restoredState` from any later callback always sees the final value.
        parent.storeRestoredState(state)

        parent.delegate?.centralManager(parent, willRestore: state)
        parent.delegate?.centralManager(parent, willRestoreState: dict)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.restoreState(state))
        }
    }

    #if os(iOS)
    func centralManager(
        _ central: CBCentralManager,
        connectionEventDidOccur event: CBConnectionEvent,
        for peripheral: CBPeripheral
    ) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.delegate?.centralManager(parent, connectionEventDidOccur: event, for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.delegate?.centralManager(parent, didUpdateANCSAuthorizationFor: peripheral)
    }
    #endif
}
