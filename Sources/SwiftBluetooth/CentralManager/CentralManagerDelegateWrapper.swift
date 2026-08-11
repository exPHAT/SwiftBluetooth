import Foundation
import CoreBluetooth

internal final class CentralManagerDelegateWrapper: NSObject, CBCentralManagerDelegate {
    private weak var parent: CentralManager?

    init(parent: CentralManager) {
        self.parent = parent
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

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)
        peripheral.updateDiscovery(.init(rssi: RSSI, advertisementData: advertisementData))

        parent.delegate?.centralManager(parent, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.discovered(peripheral, advertisementData, RSSI))
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let parent = parent else { return }

        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                let _ = parent.peripheral(peripheral) // Update underlying peripheral reference with newly restored references
            }
        }

        parent.delegate?.centralManager(parent, willRestoreState: dict)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.restoreState(dict))
        }
    }

    #if os(iOS)
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
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
