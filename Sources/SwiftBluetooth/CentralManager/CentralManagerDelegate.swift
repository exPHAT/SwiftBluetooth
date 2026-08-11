import Foundation
@preconcurrency import CoreBluetooth

/// Receives the same callbacks as `CBCentralManagerDelegate`, with ``Peripheral`` in place
/// of `CBPeripheral`.
///
/// Every method has a do-nothing default, so conform and implement only what you need.
///
/// Callbacks arrive on the queue the ``CentralManager`` was created with — the main queue
/// unless you passed one — matching how CoreBluetooth delivers them. Note that completion
/// handlers and stream values arrive on an internal queue instead, so the two aren't
/// interchangeable when you're updating UI.
public protocol CentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CentralManager)
    func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral)
    func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?)
    func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?)
    func centralManager(_ central: CentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: Peripheral)
    func centralManager(_ central: CentralManager, didDiscover peripheral: Peripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CentralManager, willRestoreState dict: [String: Any])
    func centralManager(_ central: CentralManager, didUpdateANCSAuthorizationFor peripheral: Peripheral)
}

// Default values
public extension CentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CentralManager) { }
    func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral) { }
    func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?) { }
    func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?) { }
    func centralManager(_ central: CentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: Peripheral) { }
    func centralManager(_ central: CentralManager, didDiscover peripheral: Peripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) { }
    func centralManager(_ central: CentralManager, willRestoreState dict: [String: Any]) { }
    func centralManager(_ central: CentralManager, didUpdateANCSAuthorizationFor peripheral: Peripheral) { }
}
