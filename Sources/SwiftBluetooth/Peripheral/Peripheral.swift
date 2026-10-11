import Foundation
@preconcurrency import CoreBluetooth

@dynamicMemberLookup
public final class Peripheral: NSObject {
    // Guards every mutable property below it. Never held while calling out to
    // CoreBluetooth, the delegate, or subscriber code.
    private let stateLock = NSLock()
    private var _cbPeripheral: CBPeripheral
    private var _knownCharacteristics: [CBUUID: CBCharacteristic] = [:]
    private var _discovery: DiscoveryInfo?

    // Only ever touched from `init`, which runs on a single thread, so the
    // non-atomic `lazy` initialization can't be raced.
    private lazy var wrappedDelegate: PeripheralDelegateWrapper = .init(parent: self)

    internal let eventQueue: DispatchQueue
    internal let responseMap: AsyncSubscriptionQueueMap<CBUUID, Result<Data, Error>>
    internal let writeMap: AsyncSubscriptionQueueMap<CBUUID, Error?>
    // Kept apart from `writeMap` because a descriptor and a characteristic can share a UUID,
    // and a write to one would otherwise complete a write to the other
    internal let descriptorWriteMap: AsyncSubscriptionQueueMap<CBUUID, Error?>
    internal let descriptorMap: AsyncSubscriptionQueueMap<CBUUID, Result<Any?, Error>>
    internal let eventSubscriptions: AsyncSubscriptionQueue<PeripheralEvent>

    internal var cbPeripheral: CBPeripheral {
        stateLock.lock()
        defer { stateLock.unlock() }

        return _cbPeripheral
    }

    internal let notifyingState = NotifyingTracker<CBUUID>()

    // MARK: - CBPeripheral properties
    public var name: String? { cbPeripheral.name }
    public var identifier: UUID { cbPeripheral.identifier }
    public var services: [CBService]? { cbPeripheral.services }
    public var state: CBPeripheralState { cbPeripheral.state }
    public var canSendWriteWithoutResponse: Bool { cbPeripheral.canSendWriteWithoutResponse }

    #if os(iOS)
    public var ancsAuthorized: Bool { cbPeripheral.ancsAuthorized }

    @available(*, deprecated, renamed: "ancsAuthorized")
    public var acnsAuthorized: Bool { ancsAuthorized }
    #endif

    private weak var _delegate: PeripheralDelegate?

    /// Receives the same callbacks as `CBPeripheralDelegate`, on the queue the central manager was created with.
    public var delegate: PeripheralDelegate? {
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

    /// Information from the most recent advertisement this peripheral was discovered with.
    ///
    /// This is `nil` until the peripheral has been discovered by a scan. Peripherals obtained
    /// from `retrievePeripherals(withIdentifiers:)`, `retrieveConnectedPeripherals(withServices:)`
    /// or state restoration have never been advertised to us, so they have no discovery info —
    /// identify one of those by ``identifier``, or by ``services``, which CoreBluetooth
    /// repopulates for a peripheral it restores.
    public var discoveryInfo: DiscoveryInfo? {
        stateLock.lock()
        defer { stateLock.unlock() }

        return _discovery
    }

    @available(*, deprecated, renamed: "discoveryInfo", message: "Accessing this on a peripheral that was never discovered by a scan traps. Use `discoveryInfo` instead.")
    public var discovery: DiscoveryInfo! { discoveryInfo }

    public subscript(dynamicMember member: KeyPath<Characteristic.Type, Characteristic>) -> CBCharacteristic? {
        characteristic(for: Characteristic.self[keyPath: member])
    }

    public func characteristic(for char: Characteristic) -> CBCharacteristic? {
        knownCharacteristic(for: char.uuid)
    }

    // MARK: - Initializers
    internal init(_ cbPeripheral: CBPeripheral) {
        let queue = DispatchQueue(label: "peripheral-event-queue")
        let known = Self.discoveredCharacteristics(of: cbPeripheral)

        self.eventQueue = queue
        self.responseMap = .init(queue)
        self.writeMap = .init(queue)
        self.descriptorWriteMap = .init(queue)
        self.descriptorMap = .init(queue)
        self.eventSubscriptions = .init(queue)
        self._cbPeripheral = cbPeripheral
        self._knownCharacteristics = known
        super.init()

        adoptExistingNotifications(known)
        cbPeripheral.delegate = wrappedDelegate
    }

    /// The characteristics a `CBPeripheral` has already discovered.
    ///
    /// Populated for a peripheral handed back by state restoration or retrieval, where
    /// discovery ran in a previous launch. Characteristics belong to the instance that
    /// discovered them, so this always reads from the instance being taken on.
    private static func discoveredCharacteristics(of cbPeripheral: CBPeripheral) -> [CBUUID: CBCharacteristic] {
        var known: [CBUUID: CBCharacteristic] = [:]

        for service in cbPeripheral.services ?? [] {
            for characteristic in service.characteristics ?? [] {
                known[characteristic.uuid] = characteristic
            }
        }

        return known
    }

    /// Takes on notifications that are already on for characteristics this process never
    /// subscribed to.
    ///
    /// CoreBluetooth keeps subscriptions alive across state restoration, so a characteristic
    /// can arrive already notifying in a launch that never asked for it. Recorded as an
    /// external subscription — which is what it is, from this process's point of view — so
    /// the first value stream to end doesn't switch off something a previous launch
    /// turned on.
    private func adoptExistingNotifications(_ characteristics: [CBUUID: CBCharacteristic]) {
        for (uuid, characteristic) in characteristics where characteristic.isNotifying {
            _ = notifyingState.setExternal(true, forKey: uuid)
        }
    }

    // MARK: - Internal
    internal func updateDiscovery(_ discovery: DiscoveryInfo) {
        stateLock.lock()
        defer { stateLock.unlock() }

        _discovery = discovery
    }

    internal func knownCharacteristic(for uuid: CBUUID) -> CBCharacteristic? {
        stateLock.lock()
        defer { stateLock.unlock() }

        return _knownCharacteristics[uuid]
    }

    internal func registerCharacteristics(_ characteristics: [CBCharacteristic]) {
        stateLock.lock()
        defer { stateLock.unlock() }

        for characteristic in characteristics {
            _knownCharacteristics[characteristic.uuid] = characteristic
        }
    }

    /// Points this wrapper at a new underlying `CBPeripheral`, which state restoration
    /// can hand back in place of the instance we were originally created with.
    internal func updateCBPeripheral(_ cbPeripheral: CBPeripheral) {
        // Characteristics belong to the peripheral that discovered them, so passing the old
        // instance's objects to the new one is API misuse. Reuse whatever the new instance
        // has already discovered and drop the rest.
        let known = Self.discoveredCharacteristics(of: cbPeripheral)

        stateLock.lock()
        let previous = _cbPeripheral
        _cbPeripheral = cbPeripheral
        _knownCharacteristics = known
        stateLock.unlock()

        // Only ever adds, so streams already running keep their own counts. Outside the
        // locked region because the tracker takes its own lock.
        adoptExistingNotifications(known)

        guard previous !== cbPeripheral else { return }

        previous.delegate = nil
        cbPeripheral.delegate = wrappedDelegate
    }
}

// MARK: - CBPeripheral methods
public extension Peripheral {
    func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        cbPeripheral.discoverServices(serviceUUIDs)
    }

    func discoverIncludedServices(_ serviceUUIDs: [CBUUID]?, for service: CBService) {
        cbPeripheral.discoverIncludedServices(serviceUUIDs, for: service)
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {
        cbPeripheral.discoverCharacteristics(characteristicUUIDs, for: service)
    }

    func discoverDescriptors(for characteristic: CBCharacteristic) {
        cbPeripheral.discoverDescriptors(for: characteristic)
    }

    func readValue(for characteristic: CBCharacteristic) {
        cbPeripheral.readValue(for: characteristic)
    }

    func readValue(for descriptor: CBDescriptor) {
        cbPeripheral.readValue(for: descriptor)
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        cbPeripheral.writeValue(data, for: characteristic, type: type)
    }

    func writeValue(_ data: Data, for descriptor: CBDescriptor) {
        cbPeripheral.writeValue(data, for: descriptor)
    }

    func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int {
        cbPeripheral.maximumWriteValueLength(for: type)
    }

    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic) {
        // Keep track of if the user wants notifying values outside of our subscriptions
        let shouldNotify = notifyingState.setExternal(value, forKey: characteristic.uuid)

        cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
    }

    func readRSSI() {
        cbPeripheral.readRSSI()
    }

    #if !os(macOS)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM) {
        cbPeripheral.openL2CAPChannel(PSM)
    }
    #endif
}

// All of this type's mutable state is guarded by its own lock, and the underlying
// `CBPeripheral` is safe to use from any thread, so instances can cross isolation
// boundaries. Unchecked because the compiler can't verify hand-rolled locking.
extension Peripheral: @unchecked Sendable { }
