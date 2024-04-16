import Foundation
import CoreBluetooth

public extension Peripheral {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for characteristic: CBCharacteristic) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            self.readValue(for: characteristic) { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for characteristic: Characteristic) async throws -> Data {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return try await readValue(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for descriptor: CBDescriptor) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            self.readValue(for: descriptor) { result in
                cont.resume(with: result)
            }
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
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return readValues(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.writeValue(data, for: characteristic, type: type) { error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }

                cont.resume()
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for descriptor: CBDescriptor) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.writeValue(data, for: descriptor) { error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }

                cont.resume()
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) async throws {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return try await writeValue(data, for: mappedCharacteristic, type: type)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil) async throws -> [CBService] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverServices(serviceUUIDs) { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService) async throws -> [CBCharacteristic] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverCharacteristics(characteristicUUIDs, for: service) { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService) async throws -> [CBCharacteristic] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverCharacteristics(characteristics, for: service) { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverDescriptors(for characteristic: CBCharacteristic) async throws -> [CBDescriptor] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverDescriptors(for: characteristic) { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverDescriptors(for characteristic: Characteristic) async throws -> [CBDescriptor] {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return try await discoverDescriptors(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            self.setNotifyValue(value, for: characteristic) { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func setNotifyValue(_ value: Bool, for characteristic: Characteristic) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            self.setNotifyValue(value, for: characteristic) { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readRSSI() async throws -> NSNumber {
        try await withCheckedThrowingContinuation { cont in
            self.readRSSI { result in
                cont.resume(with: result)
            }
        }
    }

    #if !os(macOS)
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM) async throws -> CBL2CAPChannel {
        try await withCheckedThrowingContinuation { cont in
            self.openL2CAPChannel(PSM) { result in
                switch result {
                case .success(let channel):
                    cont.resume(returning: channel)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }
    #endif
}
