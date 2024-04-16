import Foundation
import CoreBluetooth

internal enum CentralManagerEvent {
    case stateUpdated(CBManagerState)
    case discovered(Peripheral, [String: Any], NSNumber)
    case connected(Peripheral)
    case disconnected(Peripheral, Error?)
    case failToConnect(Peripheral, Error?)
    case restoreState([String: Any])
    case stopScan
}
