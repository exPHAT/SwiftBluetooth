import Foundation
import CoreBluetooth

public extension Peripheral {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for characteristic: CBCharacteristic) async throws -> Data {
        try await withCancellableContinuation { completion in
            self.readValue(for: characteristic, completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for characteristic: Characteristic) async throws -> Data {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await readValue(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for descriptor: CBDescriptor) async throws -> Any? {
        try await withCancellableContinuation { completion in
            self.readValue(for: descriptor, completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValues(for characteristic: CBCharacteristic) -> AsyncStream<Data> {
        .init { cont in
            var task1: AsyncSubscription<Result<Data, Error>>?
            var task2: AsyncSubscription<PeripheralEvent>?

            let cancelBoth = {
                task1?.cancel()
                task2?.cancel()
            }

            task1 = responseMap.queue(key: characteristic.uuid) { result, done in
                switch result {
                case .success(let data):
                    cont.yield(data)
                case .failure:
                    cont.finish()
                    task2?.cancel()
                    done()
                }
            } completion: { [weak self] in
                guard let self = self else { return }

                let shouldNotify = self.notifyingState.removeInternal(forKey: characteristic.uuid)

                // We should only stop notifying when we have no internal handlers waiting on it
                // and the last external `setNotifyValue` was set to false
                self.cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
            }

            task2 = eventSubscriptions.queue { event, done in
                if case .didDisconnect = event {
                    cont.finish()
                    task1?.cancel()
                    done()
                    return
                }

                guard case .updateNotificationState(let foundCharacteristic, let error) = event,
                      foundCharacteristic.uuid == characteristic.uuid,
                      (!foundCharacteristic.isNotifying || error != nil) else { return }

                cont.finish()
                task1?.cancel()
                done()
            }


            cont.onTermination = { _ in
                cancelBoth()
            }

            notifyingState.addInternal(forKey: characteristic.uuid)
            cbPeripheral.setNotifyValue(true, for: characteristic)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValues(for characteristic: Characteristic) -> AsyncStream<Data> {
        // This signature can't report the error, so an undiscovered characteristic stays fatal here
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return readValues(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) async throws {
        try await withCancellableContinuation { (completion: @escaping (Result<Void, Error>) -> Void) in
            self.writeValue(data, for: characteristic, type: type) { error in
                completion(error.map { .failure($0) } ?? .success(()))
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for descriptor: CBDescriptor) async throws {
        try await withCancellableContinuation { (completion: @escaping (Result<Void, Error>) -> Void) in
            self.writeValue(data, for: descriptor) { error in
                completion(error.map { .failure($0) } ?? .success(()))
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) async throws {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await writeValue(data, for: mappedCharacteristic, type: type)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil) async throws -> [CBService] {
        try await withCancellableContinuation { completion in
            self.discoverServices(serviceUUIDs, completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService) async throws -> [CBCharacteristic] {
        try await withCancellableContinuation { completion in
            self.discoverCharacteristics(characteristicUUIDs, for: service, completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService) async throws -> [CBCharacteristic] {
        try await withCancellableContinuation { completion in
            self.discoverCharacteristics(characteristics, for: service, completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverDescriptors(for characteristic: CBCharacteristic) async throws -> [CBDescriptor] {
        try await withCancellableContinuation { completion in
            self.discoverDescriptors(for: characteristic, completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverDescriptors(for characteristic: Characteristic) async throws -> [CBDescriptor] {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await discoverDescriptors(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic) async throws -> Bool {
        try await withCancellableContinuation { completion in
            self.setNotifyValue(value, for: characteristic, completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func setNotifyValue(_ value: Bool, for characteristic: Characteristic) async throws -> Bool {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await setNotifyValue(value, for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readRSSI() async throws -> NSNumber {
        try await withCancellableContinuation { completion in
            self.readRSSI(completionHandler: completion)
        }
    }

    #if !os(macOS)
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM) async throws -> CBL2CAPChannel {
        try await withCancellableContinuation { completion in
            self.openL2CAPChannel(PSM, completionHandler: completion)
        }
    }
    #endif
}
