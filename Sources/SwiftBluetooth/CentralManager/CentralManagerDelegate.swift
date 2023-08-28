import Foundation
import CoreBluetooth

public protocol CentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CentralManager)
    func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral)
    func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?)
    func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?)
    func centralManager(_ central: CentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: Peripheral)
    func centralManager(_ central: CentralManager, didDiscover peripheral: Peripheral, advertisementData: [String : Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CentralManager, willRestoreState dict: [String : Any])

    // TODO: ACNS support
}

// Default values
public extension CentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CentralManager) { }
    func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral) { }
    func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?) { }
    func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?) { }
    func centralManager(_ central: CentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: Peripheral) { }
    func centralManager(_ central: CentralManager, didDiscover peripheral: Peripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) { }
    func centralManager(_ central: CentralManager, willRestoreState dict: [String : Any]) { }
}
