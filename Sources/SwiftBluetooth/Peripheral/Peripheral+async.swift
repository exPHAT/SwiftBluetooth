import Foundation
@preconcurrency import CoreBluetooth

public extension Peripheral {
    /// Reads the current value of a characteristic.
    func readValue(for characteristic: CBCharacteristic) async throws -> Data {
        try await withCancellableContinuation { completion in
            self.readValue(for: characteristic, completionHandler: completion)
        }
    }

    /// Reads the current value of a characteristic that's already been discovered.
    func readValue(for characteristic: Characteristic) async throws -> Data {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await readValue(for: mappedCharacteristic)
    }

    /// Reads the current value of a descriptor.
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
            // The value and disconnection subscriptions end together, whichever finishes
            // the stream, so they're cancelled as a pair
            let subscriptions = DeferredCancellableTask()

            let values = responseMap.queue(key: characteristic.uuid) { result, done in
                switch result {
                case .success(let data):
                    cont.yield(data)
                case .failure(let error):
                    cont.finish(throwing: error)
                    subscriptions.cancel()
                }
            } completion: { [weak self] in
                guard let self = self else { return }

                let shouldNotify = self.notifyingState.removeInternal(forKey: characteristic.uuid)

                // We should only stop notifying when we have no internal handlers waiting on it
                // and the last external `setNotifyValue` was set to false
                self.cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
            }

            subscriptions.add(values)

            subscriptions.add(eventSubscriptions.queue { event, done in
                if case .didDisconnect(let error) = event {
                    cont.finish(throwing: error ?? CBError(.peripheralDisconnected))
                    subscriptions.cancel()
                    return
                }

                guard case .updateNotificationState(let foundCharacteristic, let error) = event,
                      foundCharacteristic.uuid == characteristic.uuid,
                      (!foundCharacteristic.isNotifying || error != nil) else { return }

                // Notifications being turned off is how this stream is meant to end;
                // anything else stopping them is a failure
                cont.finish(throwing: error)
                subscriptions.cancel()
            })

            cont.onTermination = { _ in
                subscriptions.cancel()
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

    /// Writes a value to a characteristic.
    ///
    /// A `.withResponse` write returns once the peripheral acknowledges it. A `.withoutResponse`
    /// write returns once it's been handed to CoreBluetooth, waiting first if the peripheral
    /// isn't ready to take one.
    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) async throws {
        try await withCancellableContinuation { completion in
            self.writeValue(data, for: characteristic, type: type, completionHandler: completion)
        }
    }

    /// Writes a value to a descriptor.
    func writeValue(_ data: Data, for descriptor: CBDescriptor) async throws {
        try await withCancellableContinuation { completion in
            self.writeValue(data, for: descriptor, completionHandler: completion)
        }
    }

    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) async throws {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { throw PeripheralError.characteristicNotFound }

        return try await writeValue(data, for: mappedCharacteristic, type: type)
    }

    /// Discovers the peripheral's services, or all of them when `serviceUUIDs` is `nil`.
    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil) async throws -> [CBService] {
        try await withCancellableContinuation { completion in
            self.discoverServices(serviceUUIDs, completionHandler: completion)
        }
    }

    /// Discovers characteristics of a service, or all of them when `characteristicUUIDs` is `nil`.
    ///
    /// A ``Characteristic`` can only be used once it's been discovered this way.
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

    /// Discovers a characteristic's descriptors.
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
    /// It can differ from what was asked for, since a value stream started by ``readValues(for:)-(CBCharacteristic)``
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

    /// Reads the current signal strength of the connection, in decibels.
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
