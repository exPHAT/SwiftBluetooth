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
        parent.eventQueue.async {
            parent.eventSubscriptions.recieve(.stateUpdated(parent.state))
            parent.delegate?.centralManagerDidUpdateState(parent)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.eventQueue.async {
            parent.connectedPeripherals.insert(peripheral)
            parent.eventSubscriptions.recieve(.connected(peripheral))
            parent.delegate?.centralManager(parent, didConnect: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.eventQueue.async {
            parent.connectedPeripherals.remove(peripheral)
            parent.eventSubscriptions.recieve(.disconnected(peripheral, error))
            peripheral.eventSubscriptions.recieve(.didDisconnect(error))
            parent.delegate?.centralManager(parent, didDisconnectPeripheral: peripheral, error: error)

            parent.removePeripheral(peripheral.cbPeripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.eventQueue.async {
            parent.eventSubscriptions.recieve(.failToConnect(peripheral, error))
            parent.delegate?.centralManager(parent, didFailToConnect: peripheral, error: error)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.eventQueue.async {
            parent.eventSubscriptions.recieve(.discovered(peripheral, advertisementData, RSSI))
            parent.delegate?.centralManager(parent, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let parent = parent else { return }

        parent.eventQueue.async {
            parent.eventSubscriptions.recieve(.restoreState(dict))
            parent.delegate?.centralManager(parent, willRestoreState: dict)
        }
    }

    #if os(iOS)
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.eventQueue.async {
            parent.delegate?.centralManager(parent, connectionEventDidOccur: event, for: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        guard let parent = parent else { return }
        let peripheral = parent.peripheral(peripheral)

        parent.eventQueue.async {
            parent.delegate?.centralManager(parent, didUpdateANCSAuthorizationFor: peripheral)
        }
    }
    #endif
}
