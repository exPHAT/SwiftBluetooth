import Foundation
import CoreBluetooth

public extension Peripheral {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for characteristic: CBCharacteristic) async -> Data {
        await withCheckedContinuation { cont in
            self.readValue(for: characteristic) { data in
                cont.resume(returning: data)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for characteristic: Characteristic) async -> Data {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return await readValue(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValue(for descriptor: CBDescriptor) async -> Any? {
        await withCheckedContinuation { cont in
            self.readValue(for: descriptor) { value in
                cont.resume(returning: value)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
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

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readValues(for characteristic: Characteristic) -> AsyncStream<Data> {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return readValues(for: mappedCharacteristic)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) async {
        await withCheckedContinuation { cont in
            self.writeValue(data, for: characteristic, type: type) {
                cont.resume()
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for descriptor: CBDescriptor) async {
        await withCheckedContinuation { cont in
            self.writeValue(data, for: descriptor) {
                cont.resume()
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) async {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        return await writeValue(data, for: mappedCharacteristic, type: type)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
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

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
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

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
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

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func discoverDescriptors(for characteristic: CBCharacteristic) async throws -> [CBDescriptor] {
        try await withCheckedThrowingContinuation { cont in
            self.discoverDescriptors(for: characteristic) { result in
                switch result {
                case .success(let descriptors):
                    cont.resume(returning: descriptors)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
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
                switch result {
                case .success(let value):
                    cont.resume(returning: value)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }


    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func setNotifyValue(_ value: Bool, for characteristic: Characteristic) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            self.setNotifyValue(value, for: characteristic) { result in
                switch result {
                case .success(let value):
                    cont.resume(returning: value)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func readRSSI() async throws -> NSNumber {
        try await withCheckedThrowingContinuation { cont in
            self.readRSSI { result in
                switch result {
                case .success(let RSSI):
                    cont.resume(returning: RSSI)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

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
}
