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
        wrappedDelegate?.centralManagerDidUpdateState(parent)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        wrappedDelegate?.centralManager(parent, didConnect: parent.peripheral(peripheral))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        wrappedDelegate?.centralManager(parent, didDisconnectPeripheral: parent.peripheral(peripheral), error: error)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        wrappedDelegate?.centralManager(parent, didFailToConnect: parent.peripheral(peripheral), error: error)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        wrappedDelegate?.centralManager(parent, didDiscover: parent.peripheral(peripheral), advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        wrappedDelegate?.centralManager(parent, willRestoreState: dict)
    }
}
