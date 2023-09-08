import Foundation
import CoreBluetooth

enum PeripheralEvent {
    case discoveredServices([CBService], Error?)
    case discoveredCharacteristics([CBCharacteristic], Error?)
}

@dynamicMemberLookup
public struct StaticCharacteristics {
    var parent: Peripheral

    public subscript(dynamicMember keyPath: KeyPath<Characteristic.Type, Characteristic>) -> CBCharacteristic {
        get {
            let characteristic = Characteristic.self[keyPath: keyPath]

            return parent.knownCharacteristics[characteristic.uuid]!
        }
    }
}

public class Peripheral: NSObject {
    private(set) var cbPeripheral: CBPeripheral
    private lazy var wrappedDelegate: PeripheralDelegateWrapper = .init(parent: self)

    internal var responseMap = AsyncSubscriptionQueueMap<CBUUID, Data>()
    internal var writeMap = AsyncSubscriptionQueueMap<CBUUID, Void>()
    internal var eventSubscriptions = AsyncSubscriptionQueue<PeripheralEvent>()

    internal var knownCharacteristics: [CBUUID: CBCharacteristic] = [:]

    public lazy var characteristics = StaticCharacteristics(parent: self)

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
}

// Completion handler methods
public extension Peripheral {
    func readValue(for characteristic: CBCharacteristic, completionHandler: @escaping (Data) -> Void) {
        responseMap.queue(key: characteristic.uuid) { data, done in
            completionHandler(data)
            done()
        }

        readValue(for: characteristic)
    }

    func readValue(for characteristic: Characteristic, completionHandler: @escaping (Data) -> Void) {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { return }

        readValue(for: mappedCharacteristic, completionHandler: completionHandler)
    }

    func readValues(for characteristic: CBCharacteristic, onValueUpdate: @escaping (Data) -> Void) -> CancellableTask {
        let subscription = responseMap.queue(key: characteristic.uuid) { data, _ in
            onValueUpdate(data)
        }

        setNotifyValue(true, for: characteristic)

        return subscription
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType, completionHandler: @escaping () -> Void) {
        if type == .withResponse {
            writeMap.queue(key: characteristic.uuid) { _, done in
                completionHandler()
                done()
            }
        }

        writeValue(data, for: characteristic, type: type)

        if type == .withoutResponse {
            completionHandler()
        }
    }

    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil, completionHandler: @escaping (Result<[CBService], Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            if case .discoveredServices(let services, let error) = event {
                if let error {
                    completionHandler(.failure(error))
                    return
                }

                completionHandler(.success(services))
                done()
            }
        }

        discoverServices(serviceUUIDs)
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            if case .discoveredCharacteristics(let characteristics, let error) = event {
                if let error {
                    completionHandler(.failure(error))
                    return
                }

                completionHandler(.success(characteristics))
                done()
            }
        }

        discoverCharacteristics(characteristicUUIDs, for: service)
    }

    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) {
        let mappedUUIDs = characteristics.map {
            guard let characteristic = knownCharacteristics[$0.uuid] else { fatalError("Characteristic \($0.uuid) not found.") }

            return characteristic.uuid
        }

        discoverCharacteristics(mappedUUIDs, for: service, completionHandler: completionHandler)
    }

    func setNotifyValue(_ value: Bool, for characteristic: Characteristic) {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        setNotifyValue(value, for: mappedCharacteristic)
    }

    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        writeValue(data, for: mappedCharacteristic, type: type)
    }

}

// Async methods
public extension Peripheral {
    func readValue(for characteristic: CBCharacteristic) async -> Data {
        await withCheckedContinuation { cont in
            self.readValue(for: characteristic) { data in
                cont.resume(returning: data)
            }
        }
    }

    func readValue(for characteristic: Characteristic) async -> Data {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return await readValue(for: mappedCharacteristic)
    }

    func readValues(for characteristic: CBCharacteristic) -> AsyncStream<Data> {
        .init { cont in
            let subscription = self.readValues(for: characteristic) { newValue in
                cont.yield(newValue)
            }

            cont.onTermination = { _ in
                subscription.cancel()
            }
        }
    }

    func readValues(for characteristic: Characteristic) -> AsyncStream<Data> {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return readValues(for: mappedCharacteristic)
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) async {
        await withCheckedContinuation { cont in
            self.writeValue(data, for: characteristic, type: type) {
                cont.resume()
            }
        }
    }

    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) async {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return await writeValue(data, for: mappedCharacteristic, type: type)
    }

    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil) async throws -> [CBService] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverServices(serviceUUIDs) { result in
                switch result {
                case .success(let services):
                    cont.resume(returning: services)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService) async throws -> [CBCharacteristic] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverCharacteristics(characteristicUUIDs, for: service) { result in
                switch result {
                case .success(let characteristics):
                    cont.resume(returning: characteristics)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService) async throws -> [CBCharacteristic] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverCharacteristics(characteristics, for: service) { result in
                switch result {
                case .success(let characteristics):
                    cont.resume(returning: characteristics)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
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
        // TODO: Set notify true when stream requested
        // Maybe store next pending notify value for when stream completed

        cbPeripheral.setNotifyValue(value, for: characteristic)
    }

    func readRSSI() {
        cbPeripheral.readRSSI()
    }

    // TODO: Do L2CAPChannel/ACNS stuff
}
