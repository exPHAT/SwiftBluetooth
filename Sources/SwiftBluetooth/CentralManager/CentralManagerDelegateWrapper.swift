import Foundation
import CoreBluetooth

class CentralManagerDelegateWrapper: NSObject, CBCentralManagerDelegate {
    private weak var parent: CentralManager?

    init(parent: CentralManager) {
        self.parent = parent
    }

    // MARK: - CBCentralManagerDelegate conformance
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let parent = self.parent else { return }

        parent.delegate?.centralManagerDidUpdateState(parent)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.stateUpdated(parent.state))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.connectedPeripherals.insert(peripheral)
        parent.delegate?.centralManager(parent, didConnect: peripheral)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.connected(peripheral))
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.connectedPeripherals.remove(peripheral)
        parent.delegate?.centralManager(parent, didDisconnectPeripheral: peripheral, error: error)

        // Not deleting peripheral instance for now. Might cause some issues for
        // people retaining a reference to a disconnected peripheral that later reconnects.
        // Maybe change this?
        //
        // parent.removePeripheral(peripheral.cbPeripheral)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.disconnected(peripheral, error))
            peripheral.eventSubscriptions.receive(.didDisconnect(error))
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.delegate?.centralManager(parent, didFailToConnect: peripheral, error: error)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.failToConnect(peripheral, error))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)
        peripheral.discovery = .init(rssi: RSSI, advertisementData: advertisementData)

        parent.delegate?.centralManager(parent, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)

        parent.eventQueue.async {
            parent.eventSubscriptions.receive(.discovered(peripheral, advertisementData, RSSI))
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let parent = parent else { return }

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
