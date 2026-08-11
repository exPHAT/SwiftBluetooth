import Foundation
import CoreBluetooth

public extension Peripheral {
    @discardableResult
    func readValue(for characteristic: CBCharacteristic, completionHandler: @escaping (Result<Data, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

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

            handle.add(task1)
            handle.add(task2)

            readValue(for: characteristic)
        }

        return handle
    }

    @discardableResult
    func readValue(for characteristic: Characteristic, completionHandler: @escaping (Result<Data, Error>) -> Void) -> CancellableTask {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else {
            completionHandler(.failure(PeripheralError.characteristicNotFound))
            return DeferredCancellableTask()
        }

        return readValue(for: mappedCharacteristic, completionHandler: completionHandler)
    }

    @discardableResult
    func readValue(for descriptor: CBDescriptor, completionHandler: @escaping (Result<Any?, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

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

            handle.add(task1)
            handle.add(task2)

            readValue(for: descriptor)
        }

        return handle
    }

    @discardableResult
    func readValues(for characteristic: CBCharacteristic, onValueUpdate: @escaping (Data) -> Void) -> CancellableTask {
        eventQueue.safeSync {
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
                self.cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
            }

            notifyingState.addInternal(forKey: characteristic.uuid)
            cbPeripheral.setNotifyValue(true, for: characteristic)

            return task2
        }
    }

    @discardableResult
    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType, completionHandler: @escaping (Error?) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

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

                handle.add(task1)
                handle.add(task2)
            }

            writeValue(data, for: characteristic, type: type)

            if type == .withoutResponse {
                completionHandler(nil)
            }
        }

        return handle
    }

    @discardableResult
    func writeValue(_ data: Data, for descriptor: CBDescriptor, completionHandler: @escaping (Error?) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard state == .connected else {
                completionHandler(CBError(.peripheralDisconnected))
                return
            }

            var task1: AsyncSubscription<Error?>?
            var task2: AsyncSubscription<PeripheralEvent>?

            task1 = writeMap.queue(key: descriptor.uuid) { error, done in
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

            handle.add(task1)
            handle.add(task2)

            writeValue(data, for: descriptor)
        }

        return handle
    }

    @discardableResult
    func discoverServices(_ serviceUUIDs: [CBUUID]? = nil, completionHandler: @escaping (Result<[CBService], Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
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
            })

            discoverServices(serviceUUIDs)
        }

        return handle
    }

    @discardableResult
    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
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
            })

            discoverCharacteristics(characteristicUUIDs, for: service)
        }

        return handle
    }

    @discardableResult
    func discoverDescriptors(for characteristic: CBCharacteristic, completionHandler: @escaping (Result<[CBDescriptor], Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
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
            })

            discoverDescriptors(for: characteristic)
        }

        return handle
    }

    @discardableResult
    func discoverCharacteristics(_ characteristics: [Characteristic], for service: CBService, completionHandler: @escaping (Result<[CBCharacteristic], Error>) -> Void) -> CancellableTask {
        discoverCharacteristics(characteristics.map(\.uuid), for: service, completionHandler: completionHandler)
    }

    @discardableResult
    func discoverDescriptors(for characteristic: Characteristic, completionHandler: @escaping (Result<[CBDescriptor], Error>) -> Void) -> CancellableTask {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else {
            completionHandler(.failure(PeripheralError.characteristicNotFound))
            return DeferredCancellableTask()
        }

        return discoverDescriptors(for: mappedCharacteristic, completionHandler: completionHandler)
    }

    @discardableResult
    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic, completionHandler: @escaping (Result<Bool, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            let shouldNotify = notifyingState.setExternal(value, forKey: characteristic.uuid)

            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            guard characteristic.isNotifying != shouldNotify else {
                completionHandler(.success(value))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
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
            })

            cbPeripheral.setNotifyValue(shouldNotify, for: characteristic)
        }

        return handle
    }

    func setNotifyValue(_ value: Bool, for characteristic: Characteristic) {
        // This signature can't report the error, so an undiscovered characteristic stays fatal here
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        setNotifyValue(value, for: mappedCharacteristic)
    }

    @discardableResult
    func setNotifyValue(_ value: Bool, for characteristic: Characteristic, completionHandler: @escaping (Result<Bool, Error>) -> Void) -> CancellableTask {
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else {
            completionHandler(.failure(PeripheralError.characteristicNotFound))
            return DeferredCancellableTask()
        }

        return setNotifyValue(value, for: mappedCharacteristic, completionHandler: completionHandler)
    }

    func writeValue(_ data: Data, for characteristic: Characteristic, type: CBCharacteristicWriteType) {
        // This signature can't report the error, so an undiscovered characteristic stays fatal here
        guard let mappedCharacteristic = knownCharacteristic(for: characteristic.uuid) else { fatalError("Characteristic \(characteristic.uuid) not found.") }

        writeValue(data, for: mappedCharacteristic, type: type)
    }

    @discardableResult
    func readRSSI(completionHandler: @escaping (Result<NSNumber, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
                if case .didDisconnect(let error) = event {
                    completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                    done()
                    return
                }

                guard case .readRSSI(let RSSI, let error) = event else { return }
                defer { done() }

                if let error = error {
                    completionHandler(.failure(error))
                } else {
                    completionHandler(.success(RSSI))
                }
            })

            readRSSI()
        }

        return handle
    }

    #if !os(macOS)
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    @discardableResult
    func openL2CAPChannel(_ PSM: CBL2CAPPSM, completionHandler: @escaping (Result<CBL2CAPChannel, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard state == .connected else {
                completionHandler(.failure(CBError(.peripheralDisconnected)))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
                if case .didDisconnect(let error) = event {
                    completionHandler(.failure(error ?? CBError(.peripheralDisconnected)))
                    done()
                    return
                }

                guard case .didOpenL2CAPChannel(let channel, let error) = event else { return }
                defer { done() }

                if let error = error {
                    completionHandler(.failure(error))
                } else if let channel = channel {
                    completionHandler(.success(channel))
                } else {
                    completionHandler(.failure(PeripheralError.unknown))
                }
            })

            openL2CAPChannel(PSM)
        }

        return handle
    }
    #endif
}
