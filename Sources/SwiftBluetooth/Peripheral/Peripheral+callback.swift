import Foundation
import CoreBluetooth

public extension Peripheral {
    func readValue(for characteristic: CBCharacteristic, completionHandler: @escaping (Result<Data, Error>) -> Void) {
        eventQueue.async { [self] in
            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            var task1: AsyncSubscription<Result<Data, Error>>?
            var task2: AsyncSubscription<PeripheralEvent>?

            task1 = responseMap.queue(key: characteristic.uuid) { result, done in
                completionHandler(result)
                task2?.cancel()
                done()
            }

            task2 = eventSubscriptions.queue { event, done in
                guard case .didDisconnect(let error) = event else { return }

                completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                task1?.cancel()
                done()
            }

            readValue(for: characteristic)
        }
    }

    func readValue(for characteristic: Characteristic, completionHandler: @escaping (Result<Data, Error>) -> Void) {
        guard let mappedCharacteristic = knownCharacteristics[characteristic.uuid] else { return }

        readValue(for: mappedCharacteristic, completionHandler: completionHandler)
    }

    func readValue(for descriptor: CBDescriptor, completionHandler: @escaping (Result<Any?, Error>) -> Void) {
        eventQueue.async { [self] in
            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            var task1: AsyncSubscription<Result<Any?, Error>>?
            var task2: AsyncSubscription<PeripheralEvent>?

            task1 = descriptorMap.queue(key: descriptor.uuid) { result, done in
                completionHandler(result)
                task2?.cancel()
                done()
            }

            task2 = eventSubscriptions.queue { event, done in
                guard case .didDisconnect(let error) = event else { return }

                completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                task1?.cancel()
                done()
            }

            readValue(for: descriptor)
        }
    }

    func readValues(for characteristic: CBCharacteristic, onValueUpdate: @escaping (Data) -> Void) -> CancellableTask {
        eventQueue.sync {
            var task1: AsyncSubscription<Result<Data, Error>>?

            let task2 = eventSubscriptions.queue { event, done in
                if case .didDisconnect = event {
                    done()
                    return
                }

                guard case .updateNotificationState(let foundCharacteristic, let error) = event,
                      foundCharacteristic.uuid == characteristic.uuid,
                      (!foundCharacteristic.isNotifying || error != nil) else { return }

                done()
            } completion: {
                task1?.cancel()
            }

            task1 = responseMap.queue(key: characteristic.uuid) { result, done in
                switch result {
                case .success(let data):
                    onValueUpdate(data)
                case .failure:
                    task2.cancel()
                    done()
                }
            } completion: { [weak self] in
                guard let self = self else { return }

                let shouldNotify = self.notifyingState.removeInternal(forKey: characteristic.uuid)
                // We should only stop notifying when we have no internal handlers waiting on it
                // and the last external `setNotifyValue` was set to false
                //
                // NOTE: External notifying tracking is currently disabled
                self.cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
            }

            notifyingState.addInternal(forKey: characteristic.uuid)
            cbPeripheral.setNotifyValue(true, for: characteristic)

            return task2
        }
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType, completionHandler: @escaping (Error?) -> Void) {
        eventQueue.async { [self] in
            guard state == .connected else {
                completionHandler(CBError(.peripheralDisconnected))
                return
            }

            if type == .withResponse {
                var task1: AsyncSubscription<Error?>?
                var task2: AsyncSubscription<PeripheralEvent>?

                task1 = writeMap.queue(key: characteristic.uuid) { error, done in
                    completionHandler(error)
                    task2?.cancel()
                    done()
                }

                task2 = eventSubscriptions.queue { event, done in
                    guard case .didDisconnect(let error) = event else { return }

                    completionHandler(error ?? CBError(.peripheralDisconnected))
                    task1?.cancel()
                    done()
                }
            }

            writeValue(data, for: characteristic, type: type)

            if type == .withoutResponse {
                completionHandler(nil)
            }
        }
    }

    func writeValue(_ data: Data, for descriptor: CBDescriptor, completionHandler: @escaping (Error?) -> Void) {
        eventQueue.async { [self] in
            writeMap.queue(key: descriptor.uuid) { error, done in
                completionHandler(error)
                done()
            }

            writeValue(data, for: descriptor)
        }
    }

    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil, completionHandler: @escaping (Result<[CBService], Error>) -> Void) {
        eventQueue.async { [self] in
            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            eventSubscriptions.queue { event, done in
                if case .didDisconnect(let error) = event {
                    completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                    done()
                    return
                }

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
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) {
        eventQueue.async { [self] in
            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            eventSubscriptions.queue { event, done in
                if case .didDisconnect(let error) = event {
                    completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                    done()
                    return
                }

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
    }

    func discoverDescriptors(for characteristic: CBCharacteristic, completionHandler: @escaping (Result<[CBDescriptor], Error>) -> Void) {
        eventQueue.async { [self] in
            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            eventSubscriptions.queue { event, done in
                if case .didDisconnect(let error) = event {
                    completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                    done()
                    return
                }

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
    }

    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) {
        discoverCharacteristics(characteristics.map(\.uuid), for: service, completionHandler: completionHandler)
    }

    func discoverDescriptors(for characteristic: Characteristic, completionHandler: @escaping (Result<[CBDescriptor], Error>) -> Void) {
        guard let characteristic = knownCharacteristics[characteristic.uuid] else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        discoverDescriptors(for: characteristic)
    }

    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic, completionHandler: @escaping (Result<Bool, Error>) -> Void) {
        eventQueue.async { [self] in
            //        let shouldNotify = notifyingState.setExternal(value, forKey: characteristic.uuid)
            let shouldNotify = value

            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            guard characteristic.isNotifying != shouldNotify else {
                completionHandler(.success(value))
                return
            }

            eventSubscriptions.queue { event, done in
                if case .didDisconnect(let error) = event {
                    completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                    done()
                    return
                }

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
        eventQueue.async { [self] in
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
    }

    #if !os(macOS)
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM, completionHandler: @escaping (Result<CBL2CAPChannel, Error>) -> Void) {
        eventQueue.async { [self] in
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
    }
    #endif
}
