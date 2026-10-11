import Foundation
@preconcurrency import CoreBluetooth

public final class CentralManager: NSObject {
    internal let centralManager: CBCentralManager

    // Strongly held here because `CBCentralManager.delegate` is weak.
    private let wrappedDelegate: CentralManagerDelegateWrapper

    internal let eventQueue: DispatchQueue
    internal let eventSubscriptions: AsyncSubscriptionQueue<CentralManagerEvent>

    /// The identifier this manager was created with, if it opted in to state restoration.
    public let restoreIdentifier: String?

    // Guards the collections below. Peripherals are created on CoreBluetooth's
    // queue but looked up from whichever thread the caller is on.
    private let stateLock = NSLock()
    private var peripheralMap: [UUID: Peripheral] = [:]
    private var _connectedPeripherals = Set<Peripheral>()
    private var _restoredState: CentralManagerRestoredState?

    /// The peripherals this manager currently has a connection to.
    ///
    /// Includes peripherals that came back already connected from state restoration or
    /// retrieval, which never produce a `didConnect`.
    public var connectedPeripherals: Set<Peripheral> {
        stateLock.lock()
        defer { stateLock.unlock() }

        return _connectedPeripherals
    }

    /// What the system handed back when it relaunched the app to restore this manager, or
    /// `nil` if this manager wasn't restored.
    ///
    /// Set before ``CentralManagerDelegate/centralManager(_:willRestore:)`` is called and
    /// never changed afterwards, so it's readable for the manager's whole life — including
    /// from code that only gets hold of the manager later. Restoration always arrives before
    /// the manager's first state update, so reading this from
    /// ``CentralManagerDelegate/centralManagerDidUpdateState(_:)``, or after
    /// waiting for `.poweredOn`, always sees the final value.
    public var restoredState: CentralManagerRestoredState? {
        stateLock.lock()
        defer { stateLock.unlock() }

        return _restoredState
    }

    internal func storeRestoredState(_ state: CentralManagerRestoredState) {
        stateLock.lock()
        defer { stateLock.unlock() }

        _restoredState = state
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

    /// Creates a central manager.
    ///
    /// - Parameters:
    ///   - delegate: Receives the same callbacks as `CBCentralManagerDelegate`. Pass it here
    ///     rather than assigning it afterwards if you use `restoreIdentifier`: restoration is
    ///     delivered during construction, so a delegate attached later misses the callback
    ///     and has to read ``restoredState`` instead.
    ///   - restoreIdentifier: Opts this manager in to state restoration. iOS preserves what
    ///     the manager is doing and relaunches the app in the background to hand it back
    ///     through ``CentralManagerDelegate/centralManager(_:willRestore:)``. The identifier
    ///     has to be the same on every launch, and the app needs the `bluetooth-central`
    ///     background mode. Ignored on platforms that don't restore, which is everything but
    ///     iOS, iPadOS and tvOS. See <doc:BackgroundOperation>.
    ///   - queue: The queue delegate callbacks arrive on. The main queue by default.
    ///   - options: Passed to `CBCentralManager` unchanged. `restoreIdentifier` wins over
    ///     `CBCentralManagerOptionRestoreIdentifierKey` given here.
    public init(delegate: CentralManagerDelegate? = nil, restoreIdentifier: String? = nil, queue: DispatchQueue? = nil, options: [String: Any]? = nil) {
        let eventQueue = DispatchQueue(label: "centralmanager-event-queue")

        var resolvedOptions = options ?? [:]
        if let restoreIdentifier = restoreIdentifier {
            resolvedOptions[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
        }

        let wrapper = CentralManagerDelegateWrapper()

        self.eventQueue = eventQueue
        self.eventSubscriptions = .init(eventQueue)
        self._delegate = delegate
        self.restoreIdentifier = resolvedOptions[CBCentralManagerOptionRestoreIdentifierKey] as? String
        self.wrappedDelegate = wrapper
        // Handed to the factory rather than assigned afterwards: state restoration is
        // delivered during construction, and a manager whose wrapper isn't the delegate
        // yet never hears about it.
        self.centralManager = CBCentralManagerFactory.instance(delegate: wrapper,
                                                               queue: queue,
                                                               options: resolvedOptions.isEmpty ? nil : resolvedOptions,
                                                               forceMock: true)
        super.init()

        wrapper.attach(to: self)
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

        // A peripheral can arrive already connected: restored by the system, or retrieved
        // after a previous launch connected it. No `didConnect` is ever delivered for those,
        // so this is the only place their connection can be picked up. The state read gates
        // the lock acquisition so the discovery path doesn't pay for it — and `markConnected`
        // takes `stateLock`, which is non-recursive, so it must stay outside the region above.
        if cbPeripheral.state == .connected {
            markConnected(peripheral)
        }

        return peripheral
    }

    /// The peripheral this manager is already tracking for an identifier, if there is one.
    ///
    /// Unlike ``retrievePeripherals(withIdentifiers:)`` this never asks CoreBluetooth about a
    /// peripheral it isn't tracking, so it starts tracking nothing new — and it works before
    /// the manager reaches `.poweredOn`, which is when a restored peripheral has to be looked
    /// up: restoration, and any `didConnect` that follows it, arrive before the first state
    /// update, while `retrievePeripherals(withIdentifiers:)` still returns nothing.
    public func peripheral(withIdentifier identifier: UUID) -> Peripheral? {
        stateLock.lock()
        defer { stateLock.unlock() }

        return peripheralMap[identifier]
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
            peripheral.eventSubscriptions.receive(.didDisconnect(error))
            eventSubscriptions.receive(.disconnected(peripheral, error))
        }

        // Scanning can't continue without a radio, and this isn't something the caller asked for
        eventSubscriptions.receive(.stopScan(error))
    }
}

// MARK: - CBCentralManager methods
public extension CentralManager {
    /// A raw passthrough to `CBCentralManager.connect`, with no timeout and no guard against
    /// asking for a peripheral that's already connected. Prefer
    /// ``connectPersistently(_:options:)`` for a request that's meant to outlive the app.
    func connect(_ peripheral: Peripheral, options: [String: Any]? = nil) {
        centralManager.connect(peripheral.cbPeripheral, options: options)
    }

    /// Asks CoreBluetooth to connect to a peripheral whenever it becomes available, and to
    /// keep asking until it does.
    ///
    /// The request has no timeout and isn't tied to a task, so it outlives this call and the
    /// app being suspended. For a manager created with a ``restoreIdentifier`` it also
    /// outlives the app being terminated: iOS relaunches the app in the background and
    /// delivers ``CentralManagerDelegate/centralManager(_:didConnect:)``.
    ///
    /// The request is consumed the moment it produces an outcome, and nothing reports that
    /// here — watch the delegate. Place it again from
    /// ``CentralManagerDelegate/centralManager(_:didFailToConnect:error:)`` and
    /// ``CentralManagerDelegate/centralManager(_:didDisconnectPeripheral:error:)`` if you're
    /// still interested, and again every time the manager reaches `.poweredOn`: a radio
    /// power-cycle discards every pending request without reporting anything.
    ///
    /// Asking twice doesn't queue two requests, so re-arming when one is already in place is
    /// harmless. Asking for a peripheral that's already connected isn't: CoreBluetooth
    /// answers with another `didConnect`, so that case is refused here instead. `.connecting`
    /// is deliberately allowed through — after a radio power-cycle CoreBluetooth can still
    /// report the stale state while the pending request is already gone, and re-arming is
    /// exactly what this API is for.
    ///
    /// - Returns: Whether a connection was requested. `false` when the peripheral was
    ///   already connected, in which case there is nothing to wait for.
    @discardableResult
    func connectPersistently(_ peripheral: Peripheral, options: [String: Any]? = nil) -> Bool {
        guard peripheral.state != .connected else { return false }

        centralManager.connect(peripheral.cbPeripheral, options: options)
        return true
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
        eventSubscriptions.receive(.stopScan(nil))
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
extension CentralManager: @unchecked Sendable { }
