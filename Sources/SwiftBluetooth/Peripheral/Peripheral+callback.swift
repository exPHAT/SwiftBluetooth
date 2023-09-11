import Foundation
import CoreBluetooth

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
        } completion: { [weak self] in
            guard let self else { return }

            let shouldNotify = self.notifyingState.removeInternal(forKey: characteristic.uuid)

            // We should only stop notifying when we have no internal handlers waiting on it
            // and the last external `setNotifyValue` was set to false
            self.cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
        }

        notifyingState.addInternal(forKey: characteristic.uuid)
        cbPeripheral.setNotifyValue(true, for: characteristic)

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
