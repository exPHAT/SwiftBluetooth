import Foundation
import CoreBluetooth

public class Peripheral: NSObject {
    private(set) var cbPeripheral: CBPeripheral
    private lazy var wrappedDelegate: PeripheralDelegateWrapper = .init(parent: self)

    internal var responseMap = AsyncSubscriptionQueueMap<CBUUID, Data>()
    internal var writeMap = AsyncSubscriptionQueueMap<CBUUID, Void>()
    internal var descriptorMap = AsyncSubscriptionQueueMap<CBUUID, Any?>()
    internal var eventSubscriptions = AsyncSubscriptionQueue<PeripheralEvent>()

    internal var knownCharacteristics: [CBUUID: CBCharacteristic] = [:]

    internal var notifyingState = NotifyingTracker<CBUUID>()

    // MARK: - CBPeripheral properties
    public var name: String? { cbPeripheral.name }
    public var identifier: UUID { cbPeripheral.identifier }
    public var services: [CBService]? { cbPeripheral.services }
    public var state: CBPeripheralState { cbPeripheral.state }
    public var canSendWriteWithoutResponse: Bool { cbPeripheral.canSendWriteWithoutResponse }

    #if os(iOS)
    public var acnsAuthorized: Bool { cbPeripheral.ancsAuthorized }
    #endif

    public var delegate: PeripheralDelegate?

    // MARK: - CBPeripheral initializers
    public init(_ cbPeripheral: CBPeripheral) {
        self.cbPeripheral = cbPeripheral
        super.init()

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
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM) {
        cbPeripheral.openL2CAPChannel(PSM)
    }
    #endif
}
