import Foundation
import CoreBluetooth

class CentralManagerDelegateWrapper: NSObject, CBCentralManagerDelegate {
    private weak var parent: CentralManager?

    init(parent: CentralManager) {
        self.parent = parent
    }

    // MARK: - CBCentralManagerDelegate conformance

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let parent else { return }
        parent.eventSubscriptions.recieve(.stateUpdated(parent.state))
        parent.delegate?.centralManagerDidUpdateState(parent)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let parent else { return }
        parent.eventSubscriptions.recieve(.connected(parent.peripheral(peripheral)))
        parent.delegate?.centralManager(parent, didConnect: parent.peripheral(peripheral))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let parent else { return }
        parent.eventSubscriptions.recieve(.disconnected(parent.peripheral(peripheral), error))
        parent.delegate?.centralManager(parent, didDisconnectPeripheral: parent.peripheral(peripheral), error: error)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let parent else { return }
        parent.eventSubscriptions.recieve(.failToConnect(parent.peripheral(peripheral), error))
        parent.delegate?.centralManager(parent, didFailToConnect: parent.peripheral(peripheral), error: error)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let parent else { return }
        parent.eventSubscriptions.recieve(.discovered(parent.peripheral(peripheral), advertisementData, RSSI))
        parent.delegate?.centralManager(parent, didDiscover: parent.peripheral(peripheral), advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        guard let parent else { return }
        parent.delegate?.centralManager(parent, willRestoreState: dict)
    }
}
