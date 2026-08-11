import Foundation
import CoreBluetooth

public extension Peripheral {
    func readValue(for characteristic: CBCharacteristic) async throws -> Data {
        try await withCancellableContinuation { completion in
            self.readValue(for: characteristic, completionHandler: completion)
        }
    }

    func readValue(for characteristic: Characteristic) async throws -> Data {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await readValue(for: mappedCharacteristic)
    }

    func readValue(for descriptor: CBDescriptor) async throws -> Any? {
        try await withCancellableContinuation { completion in
            self.readValue(for: descriptor, completionHandler: completion)
        }
    }

    /// Subscribes to a characteristic, yielding each value the peripheral sends.
    ///
    /// The stream finishes normally when notifications are turned off, and throws if the
    /// peripheral disconnects or reports an error while it's subscribed.
    func readValues(for characteristic: CBCharacteristic) -> AsyncThrowingStream<Data, Error> {
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
                case .failure(let error):
                    cont.finish(throwing: error)
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
                if case .didDisconnect(let error) = event {
                    cont.finish(throwing: error ?? CBError(.peripheralDisconnected))
                    task1?.cancel()
                    done()
                    return
                }

                guard case .updateNotificationState(let foundCharacteristic, let error) = event,
                      foundCharacteristic.uuid == characteristic.uuid,
                      (!foundCharacteristic.isNotifying || error != nil) else { return }

                // Notifications being turned off is how this stream is meant to end;
                // anything else stopping them is a failure
                cont.finish(throwing: error)
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

    func readValues(for characteristic: Characteristic) -> AsyncThrowingStream<Data, Error> {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else {
            // Reported through the stream rather than by throwing here, so callers have
            // a single place to handle failures
            return .init { $0.finish(throwing: PeripheralError.characteristicNotFound) }
        }

        return readValues(for: mappedCharacteristic)
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) async throws {
        try await withCancellableContinuation { completion in
            self.writeValue(data, for: characteristic, type: type, completionHandler: completion)
        }
    }

    func writeValue(_ data: Data, for descriptor: CBDescriptor) async throws {
        try await withCancellableContinuation { completion in
            self.writeValue(data, for: descriptor, completionHandler: completion)
        }
    }

    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) async throws {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await writeValue(data, for: mappedCharacteristic, type: type)
    }

    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil) async throws -> [CBService] {
        try await withCancellableContinuation { completion in
            self.discoverServices(serviceUUIDs, completionHandler: completion)
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService) async throws -> [CBCharacteristic] {
        try await withCancellableContinuation { completion in
            self.discoverCharacteristics(characteristicUUIDs, for: service, completionHandler: completion)
        }
    }

    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService) async throws -> [CBCharacteristic] {
        try await withCancellableContinuation { completion in
            self.discoverCharacteristics(characteristics, for: service, completionHandler: completion)
        }
    }

    func discoverDescriptors(for characteristic: CBCharacteristic) async throws -> [CBDescriptor] {
        try await withCancellableContinuation { completion in
            self.discoverDescriptors(for: characteristic, completionHandler: completion)
        }
    }

    func discoverDescriptors(for characteristic: Characteristic) async throws -> [CBDescriptor] {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await discoverDescriptors(for: mappedCharacteristic)
    }

    /// Turns notifications for a characteristic on or off.
    ///
    /// Whether the characteristic ends up notifying is readable from `characteristic.isNotifying`.
    /// It can differ from what was asked for, since a value stream started by ``readValues(for:)``
    /// keeps notifications on until it ends.
    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic) async throws {
        try await withCancellableContinuation { completion in
            self.setNotifyValue(value, for: characteristic, completionHandler: completion)
        }
    }

    func setNotifyValue(_ value: Bool, for characteristic: Characteristic) async throws {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await setNotifyValue(value, for: mappedCharacteristic)
    }

    func readRSSI() async throws -> NSNumber {
        try await withCancellableContinuation { completion in
            self.readRSSI(completionHandler: completion)
        }
    }

    #if !os(macOS)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM) async throws -> CBL2CAPChannel {
        try await withCancellableContinuation { completion in
            self.openL2CAPChannel(PSM, completionHandler: completion)
        }
    }
    #endif
}
