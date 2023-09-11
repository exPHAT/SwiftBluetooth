import Foundation
import CoreBluetooth

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
