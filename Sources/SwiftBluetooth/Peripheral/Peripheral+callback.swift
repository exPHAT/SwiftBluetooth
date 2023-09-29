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

    func readValue(for descriptor: CBDescriptor, completionHandler: @escaping (Any?) -> Void) {
        descriptorMap.queue(key: descriptor.uuid) { value, done in
            completionHandler(value)
            done()
        }

        readValue(for: descriptor)
    }

    func readValues(for characteristic: CBCharacteristic, onValueUpdate: @escaping (Data) -> Void) -> CancellableTask {
        let valueSubscription = responseMap.queue(key: characteristic.uuid) { data, _ in
            onValueUpdate(data)
        } completion: { [weak self] in
            guard let self = self else { return }

            let shouldNotify = self.notifyingState.removeInternal(forKey: characteristic.uuid)
            // We should only stop notifying when we have no internal handlers waiting on it
            // and the last external `setNotifyValue` was set to false
            //
            // NOTE: External notifying tracking is currently disabled
            self.cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
        }

        let eventSubscription = eventSubscriptions.queue { event, done in
            guard case .updateNotificationState(let foundCharacteristic, _) = event,
                  foundCharacteristic.uuid == characteristic.uuid,
                  !foundCharacteristic.isNotifying else { return }

            done()
        } completion: {
            valueSubscription.cancel()
        }

        notifyingState.addInternal(forKey: characteristic.uuid)
        cbPeripheral.setNotifyValue(true, for: characteristic)

        return eventSubscription
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

    func writeValue(_ data: Data, for descriptor: CBDescriptor, completionHandler: @escaping () -> Void) {
        writeMap.queue(key: descriptor.uuid) { _, done in
            completionHandler()
            done()
        }

        writeValue(data, for: descriptor)
    }

    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil, completionHandler: @escaping (Result<[CBService], Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            guard case .discoveredServices(let services, let error) = event else { return }
            defer { done() }

            if let error = error {
                completionHandler(.failure(error))
                return
            }

            completionHandler(.success(services))
        }

        discoverServices(serviceUUIDs)
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            guard case .discoveredCharacteristics(let forService, let characteristics, let error) = event,
                  forService.uuid == service.uuid else { return }
            defer { done() }

            if let error = error {
                completionHandler(.failure(error))
                return
            }

            completionHandler(.success(characteristics))
        }

        discoverCharacteristics(characteristicUUIDs, for: service)
    }

    func discoverDescriptors(for characteristic: CBCharacteristic, completionHandler: @escaping (Result<[CBDescriptor], Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            guard case .discoveredDescriptors(let forCharacteristic, let descriptors, let error) = event,
                  forCharacteristic.uuid == characteristic.uuid else { return }
            defer { done() }

            if let error = error {
                completionHandler(.failure(error))
                return
            }

            completionHandler(.success(descriptors))
        }

        discoverDescriptors(for: characteristic)
    }

    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) {
        discoverCharacteristics(characteristics.map(\.uuid), for: service, completionHandler: completionHandler)
    }

    func discoverDescriptors(for characteristic: Characteristic, completionHandler: @escaping (Result<[CBDescriptor], Error>) -> Void) {
        guard let characteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        discoverDescriptors(for: characteristic)
    }

    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic, completionHandler: @escaping (Result<Bool, Error>) -> Void) {
//        let shouldNotify = notifyingState.setExternal(value, forKey: characteristic.uuid)
        let shouldNotify = value

        guard characteristic.isNotifying != shouldNotify else {
            completionHandler(.success(value))
            return
        }

        eventSubscriptions.queue { event, done in
            guard case .updateNotificationState(let forCharacteristic, let error) = event,
                  forCharacteristic.uuid == characteristic.uuid else { return }
            defer { done() }

            if let error = error {
                completionHandler(.failure(error))
                return
            }

            completionHandler(.success(characteristic.isNotifying))
        }

        cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
    }

    func setNotifyValue(_ value: Bool, for characteristic: Characteristic) {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        setNotifyValue(value, for: mappedCharacteristic)
    }

    func setNotifyValue(_ value: Bool, for characteristic: Characteristic, completionHandler: @escaping (Result<Bool, Error>) -> Void) {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        setNotifyValue(value, for: mappedCharacteristic, completionHandler: completionHandler)
    }


    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        writeValue(data, for: mappedCharacteristic, type: type)
    }

    func readRSSI(completionHandler: @escaping (Result<NSNumber, Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            guard case .readRSSI(let RSSI, let error) = event else { return }
            defer { done() }

            if let error = error {
                completionHandler(.failure(error))
            } else {
                completionHandler(.success(RSSI))
            }
        }

        readRSSI()
    }

    #if !os(macOS)
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM, completionHandler: @escaping (Result<CBL2CAPChannel, Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            guard case .didOpenL2CAPChannel(let channel, let error) = event else { return }
            defer { done() }

            if let error = error {
                completionHandler(.failure(error))
            } else if let channel = channel {
                completionHandler(.success(channel))
            } else {
                completionHandler(.failure(PeripheralError.unknown))
            }
        }

        openL2CAPChannel(PSM)
    }
    #endif
}
