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
    /// Called whenever the manager's state changes.
    ///
    /// Losing the radio — any state that isn't `.poweredOn` — ends every connection and
    /// discards every pending connect, and CoreBluetooth reports no disconnection for any
    /// of them. Treat it as everything having gone away, and re-arm what you still want
    /// from the next `.poweredOn`.
    func centralManagerDidUpdateState(_ central: CentralManager)
    func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral)
    /// Not called for a peripheral this manager isn't tracking — an outcome for a peripheral
    /// it was never told about is dropped rather than adopted.
    func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?)
    /// Not called for a peripheral this manager isn't tracking — an outcome for a peripheral
    /// it was never told about is dropped rather than adopted.
    func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?)
    func centralManager(_ central: CentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: Peripheral)
    func centralManager(_ central: CentralManager, didDiscover peripheral: Peripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    /// Called when this manager is being restored from a previous launch of the app.
    ///
    /// Only for a manager created with a ``CentralManager/restoreIdentifier``. This is the
    /// first callback there is — it arrives before ``centralManagerDidUpdateState(_:)``, so
    /// the manager may not have reported a state yet, and it's delivered during construction,
    /// so only a delegate passed to
    /// ``CentralManager/init(delegate:restoreIdentifier:queue:options:)`` receives it.
    /// A delegate attached afterwards can read ``CentralManager/restoredState`` instead.
    ///
    /// ``centralManager(_:willRestoreState:)`` carries the same thing untranslated, and is
    /// called straight after this one.
    func centralManager(_ central: CentralManager, willRestore state: CentralManagerRestoredState)
    /// The untranslated form of ``centralManager(_:willRestore:)``, mirroring
    /// `CBCentralManagerDelegate`. Restored peripherals arrive as `CBPeripheral`; the
    /// same delivery rules apply.
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
    func centralManager(_ central: CentralManager, willRestore state: CentralManagerRestoredState) { }
    func centralManager(_ central: CentralManager, willRestoreState dict: [String: Any]) { }
    func centralManager(_ central: CentralManager, didUpdateANCSAuthorizationFor peripheral: Peripheral) { }
}
