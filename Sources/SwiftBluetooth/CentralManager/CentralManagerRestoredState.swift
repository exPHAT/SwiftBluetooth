import Foundation
@preconcurrency import CoreBluetooth

/// The state a ``CentralManager`` was relaunched to take back over.
///
/// iOS preserves what a manager created with a ``CentralManager/restoreIdentifier`` was doing
/// and hands it back when it relaunches the app to finish that work. This arrives before any
/// other callback — before the manager has even reported its state. See <doc:BackgroundOperation>.
public struct CentralManagerRestoredState {
    /// The peripherals the previous launch was connected to, or still trying to connect to.
    ///
    /// These are already registered with the manager, so they're the same objects
    /// ``CentralManager/retrievePeripherals(withIdentifiers:)`` hands back. Check
    /// ``Peripheral/state`` to tell a live connection from one that's still pending:
    /// restoration isn't a connection event, and no `didConnect` is delivered for a
    /// peripheral that was already connected.
    ///
    /// They have no ``Peripheral/discoveryInfo`` — they were never advertised to this
    /// process — but ``Peripheral/services`` and any characteristics CoreBluetooth
    /// preserved are there.
    public let peripherals: [Peripheral]

    /// The services the previous launch was scanning for, or `nil` if it wasn't scanning.
    ///
    /// The scan is still running: ``CentralManager/isScanning`` reports `true` and discoveries
    /// reach the delegate, but no stream or callback created in this launch is attached to it.
    /// Call ``CentralManager/stopScan()``, or start your own scan, which replaces it.
    public let scanServices: [CBUUID]?

    /// The options the previous launch was scanning with, if it was scanning.
    public let scanOptions: [String: Any]?

    /// Everything CoreBluetooth handed over, including keys this type doesn't model.
    public let dictionary: [String: Any]

    /// Whether the previous launch was scanning when the app went away.
    public var wasScanning: Bool { scanServices != nil || scanOptions != nil }
}

// `dictionary` and `scanOptions` are CoreBluetooth's own values, which carry no Sendable
// annotations. Unchecked for the same reason `UncheckedTransfer` exists.
extension CentralManagerRestoredState: @unchecked Sendable { }
