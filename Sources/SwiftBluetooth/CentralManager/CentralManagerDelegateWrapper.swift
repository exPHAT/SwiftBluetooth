import Foundation
import CoreBluetooth

class CentralManagerDelegateWrapper: NSObject, CBCentralManagerDelegate {
    private var parent: CentralManager

    init(parent: CentralManager) {
        self.parent = parent
    }

    var wrappedDelegate: CentralManagerDelegate? {
        parent.delegate
    }

    // MARK: - CBCentralManagerDelegate conformance

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        parent.eventSubscriptions.recieve(.stateUpdated(parent.state))
        wrappedDelegate?.centralManagerDidUpdateState(parent)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        parent.eventSubscriptions.recieve(.connected(parent.peripheral(peripheral)))
        wrappedDelegate?.centralManager(parent, didConnect: parent.peripheral(peripheral))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        parent.eventSubscriptions.recieve(.disconnected(parent.peripheral(peripheral), error))
        wrappedDelegate?.centralManager(parent, didDisconnectPeripheral: parent.peripheral(peripheral), error: error)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        parent.eventSubscriptions.recieve(.failToConnect(parent.peripheral(peripheral), error))
        wrappedDelegate?.centralManager(parent, didFailToConnect: parent.peripheral(peripheral), error: error)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        parent.eventSubscriptions.recieve(.discovered(parent.peripheral(peripheral), advertisementData, RSSI))
        wrappedDelegate?.centralManager(parent, didDiscover: parent.peripheral(peripheral), advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        wrappedDelegate?.centralManager(parent, willRestoreState: dict)
    }
}
