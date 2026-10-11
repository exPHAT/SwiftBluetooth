import Foundation
@preconcurrency import CoreBluetooth

internal enum CentralManagerEvent {
    case stateUpdated(CBManagerState)
    case discovered(Peripheral, [String: Any], NSNumber)
    case connected(Peripheral)
    case disconnected(Peripheral, Error?)
    case failToConnect(Peripheral, Error?)
    case restoreState(CentralManagerRestoredState)
    /// Carries an error when scanning stopped because the manager can no longer scan,
    /// rather than because someone asked it to stop.
    case stopScan(Error?)
}
