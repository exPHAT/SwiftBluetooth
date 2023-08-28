import Foundation
import CoreBluetooth

public protocol Characteristic: Hashable, RawRepresentable where RawValue == String {
    var uuid: UUID { get }
}

public extension Characteristic {
    var uuid: UUID {
        .init(uuidString: rawValue)!
    }
}

enum UnknownCharacteristic: String, Characteristic {
    case thing = "asdfsadfs"
}

public class Peripheral: NSObject {
    private(set) var cbPeripheral: CBPeripheral
    private lazy var wrappedDelegate: PeripheralDelegateWrapper = .init(parent: self)

    internal var responseMap = AsyncResponseMap<CBUUID, Data>()
    internal var writeMap = AsyncResponseMap<CBUUID, Void>()

    internal var characteristicMap: [CBUUID: CBCharacteristic] = [:]

    // MARK: - CBPeripheral properties
    public var name: String? { cbPeripheral.name }
    public var identifier: UUID { cbPeripheral.identifier }
    public var services: [CBService]? { cbPeripheral.services }
    public var state: CBPeripheralState { cbPeripheral.state }
    public var canSendWriteWithoutResponse: Bool { cbPeripheral.canSendWriteWithoutResponse }
//    var rssi: NSNumber? { cbPeripheral.rssi }

    public var delegate: PeripheralDelegate?


    // MARK: - CBPeripheral initializers
    public init(_ cbPeripheral: CBPeripheral) {
        self.cbPeripheral = cbPeripheral
        super.init()

        cbPeripheral.delegate = wrappedDelegate
    }

    public func readValue(for characteristic: CBCharacteristic, completionHandler: @escaping (Data) -> Void) {
        responseMap.request(key: characteristic.uuid, completionHandler: completionHandler)

        readValue(for: characteristic)
    }

    public func readValue(for characteristic: CBCharacteristic) async -> Data {
        await withCheckedContinuation { cont in
            self.readValue(for: characteristic) { data in
                cont.resume(returning: data)
            }
        }
    }

    public func readValues(for characteristic: CBCharacteristic, onValueUpdate: @escaping (Data) -> Void) {
        responseMap.request(key: characteristic.uuid, singleUse: false, completionHandler: onValueUpdate)

        setNotifyValue(true, for: characteristic)
        readValue(for: characteristic)
    }

    public func readValues(for characteristic: CBCharacteristic) -> AsyncStream<Data> {
        .init { cont in
            cont.onTermination = { _ in
                // TODO: Decide if this is a bad idea
                self.setNotifyValue(false, for: characteristic)
            }

            self.readValues(for: characteristic) { newValue in
                cont.yield(newValue)
            }
        }
    }

    public func writeValue(_ data: Data, for characteristic: CBCharacteristic) {
        writeValue(data, for: characteristic, type: .withoutResponse)
    }

    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, completionHandler: @escaping () -> Void) {
        writeMap.request(key: characteristic.uuid, completionHandler: completionHandler)

        writeValue(data, for: characteristic, type: .withResponse)
    }

    public func writeValue(_ data: Data, for characteristic: CBCharacteristic) async {
        await withCheckedContinuation { cont in
            self.writeValue(data, for: characteristic) {
                cont.resume()
            }
        }
    }

    // MARK: - CBPeripheral methods
    public func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        cbPeripheral.discoverServices(serviceUUIDs)
    }

    public func discoverIncludedServices(_ serviceUUIDs: [CBUUID]?, for service: CBService) {
        cbPeripheral.discoverIncludedServices(serviceUUIDs, for: service)
    }

    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {
        cbPeripheral.discoverCharacteristics(characteristicUUIDs, for: service)
    }

    public func discoverDescriptors(for characteristic: CBCharacteristic) {
        cbPeripheral.discoverDescriptors(for: characteristic)
    }

    public func readValue(for characteristic: CBCharacteristic) {
        cbPeripheral.readValue(for: characteristic)
    }

    public func readValue(for descriptor: CBDescriptor) {
        cbPeripheral.readValue(for: descriptor)
    }

    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        cbPeripheral.writeValue(data, for: characteristic, type: type)
    }

    public func writeValue(_ data: Data, for descriptor: CBDescriptor) {
        cbPeripheral.writeValue(data, for: descriptor)
    }

    public func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int {
        cbPeripheral.maximumWriteValueLength(for: type)
    }

    public func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic) {
        // TODO: Set notify true when stream requested
        // Maybe store next pending notify value for when stream completed

        cbPeripheral.setNotifyValue(value, for: characteristic)
    }

    public func readRSSI() {
        cbPeripheral.readRSSI()
    }

    // TODO: Do L2CAPChannel/ACNS stuff
}

//extension Peripheral where Value == UnknownCharacteristic {
//    init(_ peripheral: CBPeripheral) {
//        self.init<UnknownCharacteristic>(peripheral)
//    }
//}
