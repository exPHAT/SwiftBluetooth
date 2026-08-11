import Foundation
import CoreBluetooth

public class CentralManager: NSObject {
    internal let centralManager: CBCentralManager

    // Only ever touched from `init`, which runs on a single thread, so the
    // non-atomic `lazy` initialization can't be raced.
    private lazy var wrappedDelegate: CentralManagerDelegateWrapper = .init(parent: self)

    internal let eventQueue: DispatchQueue
    internal let eventSubscriptions: AsyncSubscriptionQueue<CentralManagerEvent>

    // Guards the two collections below. Peripherals are created on CoreBluetooth's
    // queue but looked up from whichever thread the caller is on.
    private let stateLock = NSLock()
    private var peripheralMap: [UUID: Peripheral] = [:]
    private var _connectedPeripherals = Set<Peripheral>()

    internal var connectedPeripherals: Set<Peripheral> {
        stateLock.lock()
        defer { stateLock.unlock() }

        return _connectedPeripherals
    }

    // MARK: - CBCentralManager properties
    private weak var _delegate: CentralManagerDelegate?

    /// Receives the same callbacks as `CBCentralManagerDelegate`, on the queue this manager was created with.
    public var delegate: CentralManagerDelegate? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }

            return _delegate
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }

            _delegate = newValue
        }
    }
    public var state: CBManagerState { centralManager.state }
    public var isScanning: Bool { centralManager.isScanning }

    @available(iOS, deprecated: 13.1)
    public var authorization: CBManagerAuthorization { centralManager.authorization }

    // MARK: - CBCentralManager initializers
    convenience override init() {
        self.init(delegate: nil, queue: nil, options: nil)
    }

    public init(delegate: CentralManagerDelegate? = nil, queue: DispatchQueue? = nil, options: [String: Any]? = nil) {
        let eventQueue = DispatchQueue(label: "centralmanager-event-queue")

        self.eventQueue = eventQueue
        self.eventSubscriptions = .init(eventQueue)
        self._delegate = delegate
        self.centralManager = CBCentralManagerFactory.instance(delegate: nil, queue: queue, options: options, forceMock: true)
        super.init()

        centralManager.delegate = wrappedDelegate
    }

    // MARK: - Internal
    internal func peripheral(_ cbPeripheral: CBPeripheral) -> Peripheral {
        stateLock.lock()
        let found = peripheralMap[cbPeripheral.identifier]
        // Creating it while holding the lock matters: a `Peripheral` makes itself the
        // delegate of its `CBPeripheral`, so a second one built for the same identifier
        // would take over delegate callbacks meant for the one we keep
        let peripheral = found ?? Peripheral(cbPeripheral)
        if found == nil {
            // Save peripheral for later so the same identifier always maps to the same object
            peripheralMap[cbPeripheral.identifier] = peripheral
        }
        stateLock.unlock()

        // Sometimes state restoration will create a new instance of the same peripheral with the same identifier.
        // If any events come up with a mismatched instance, we should update them.
        // Done outside the lock because it takes the peripheral's own lock.
        if let found = found, found.cbPeripheral !== cbPeripheral {
            found.updateCBPeripheral(cbPeripheral)
        }

        return peripheral
    }

    /// Looks up a peripheral we're already tracking, without creating one for a peripheral we aren't.
    ///
    /// Used for events that report a peripheral going away, where taking on a peripheral we've
    /// never seen would mean building a second wrapper for it — one that takes over delegate
    /// callbacks from whichever wrapper the caller is still holding.
    internal func existingPeripheral(_ cbPeripheral: CBPeripheral) -> Peripheral? {
        stateLock.lock()
        defer { stateLock.unlock() }

        return peripheralMap[cbPeripheral.identifier]
    }

    @discardableResult
    internal func removePeripheral(_ cbPeripheral: CBPeripheral) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        return peripheralMap.removeValue(forKey: cbPeripheral.identifier) != nil
    }

    internal func markConnected(_ peripheral: Peripheral) {
        stateLock.lock()
        defer { stateLock.unlock() }

        _connectedPeripherals.insert(peripheral)
    }

    internal func markDisconnected(_ peripheral: Peripheral) {
        stateLock.lock()
        defer { stateLock.unlock() }

        _connectedPeripherals.remove(peripheral)
    }

    internal func isConnected(_ peripheral: Peripheral) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        return _connectedPeripherals.contains(peripheral)
    }

    /// Drops every peripheral we're tracking and reports them as disconnected.
    /// CoreBluetooth invalidates peripherals when the radio goes away without
    /// delivering a disconnection for any of them.
    internal func invalidatePeripherals(with error: Error) {
        stateLock.lock()
        let peripherals = Array(peripheralMap.values)
        _connectedPeripherals.removeAll()
        stateLock.unlock()

        for peripheral in peripherals {
            peripheral.eventSubscriptions.recieve(.didDisconnect(error))
            eventSubscriptions.recieve(.disconnected(peripheral, error))
        }

        eventSubscriptions.recieve(.stopScan)
    }
}

// MARK: - CBCentralManager methods
public extension CentralManager {
    func connect(_ peripheral: Peripheral, options: [String: Any]? = nil) {
        centralManager.connect(peripheral.cbPeripheral, options: options)
    }

    func cancelPeripheralConnection(_ peripheral: Peripheral) {
        centralManager.cancelPeripheralConnection(peripheral.cbPeripheral)
    }

    func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [Peripheral] {
        centralManager.retrieveConnectedPeripherals(withServices: services).map(peripheral(_:))
    }

    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [Peripheral] {
        centralManager.retrievePeripherals(withIdentifiers: identifiers).map(peripheral(_:))
    }

    func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]? = nil) {
        centralManager.scanForPeripherals(withServices: services, options: options)
    }

    /// Stops scanning for peripherals.
    ///
    /// Only one scan can be in progress at a time, so this ends every scan currently running,
    /// finishing their streams and cancelling their callbacks.
    func stopScan() {
        eventSubscriptions.recieve(.stopScan)
        centralManager.stopScan()
    }

    /// Releases this manager's reference to a peripheral it is no longer interested in.
    ///
    /// Every peripheral seen by this manager — including ones that only advertised during a scan —
    /// is kept for its lifetime, so that a device which reconnects is always represented by the same
    /// object. Long-running scans in busy environments can accumulate a lot of them, and this drops
    /// the ones you're finished with.
    ///
    /// Connected peripherals are never dropped, since events still need to be routed to them.
    /// Retrieving or rediscovering a peripheral afterwards produces a new object, so any
    /// ``Peripheral`` you're still holding on to will no longer be equal to it, and will no
    /// longer be told about the peripheral disconnecting.
    ///
    /// - Returns: whether the peripheral was being tracked and has now been dropped.
    @discardableResult
    func forgetPeripheral(_ peripheral: Peripheral) -> Bool {
        guard peripheral.state == .disconnected, !isConnected(peripheral) else { return false }

        return removePeripheral(peripheral.cbPeripheral)
    }
}

// All of this type's mutable state is guarded by its own lock, and the underlying
// `CBCentralManager` is safe to use from any thread, so instances can cross isolation
// boundaries. Unchecked because the compiler can't verify hand-rolled locking.
@available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
extension CentralManager: @unchecked Sendable { }
