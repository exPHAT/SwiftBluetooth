import Foundation
import CoreBluetooth

public extension CentralManager {
    @discardableResult
    func waitUntilReady(completionHandler: @escaping (Result<Void, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard state != .poweredOn else {
                completionHandler(.success(Void()))
                return
            }

            guard state != .unauthorized else {
                completionHandler(.failure(CentralError.unauthorized))
                return
            }

            guard state != .unsupported else {
                completionHandler(.failure(CentralError.unavailable))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
                guard case .stateUpdated(let state) = event else { return }

                switch state {
                case .poweredOn:
                    completionHandler(.success(Void()))
                case .unauthorized:
                    completionHandler(.failure(CentralError.unauthorized))
                case .unsupported:
                    completionHandler(.failure(CentralError.unavailable))
                default:
                    return
                }

                done()
            })
        }

        return handle
    }

    @discardableResult
    func connect(_ peripheral: Peripheral, timeout timeoutInterval: TimeInterval = .infinity, options: [String: Any]? = nil, completionHandler: @escaping (Result<Peripheral, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard peripheral.state != .connected else {
                completionHandler(.success(peripheral))
                return
            }

            var timeout: DispatchTimeout?
            let task = eventSubscriptions.queue { event, done in
                let result: Result<Peripheral, Error>

                switch event {
                case .connected(let connected):
                    guard connected == peripheral else { return }
                    result = .success(peripheral)
                case .disconnected(let disconnected, let error):
                    guard disconnected == peripheral else { return }
                    result = .failure(error ?? CentralError.unknown)
                case .failToConnect(let failed, let error):
                    guard failed == peripheral else { return }
                    result = .failure(error ?? CentralError.unknown)
                default:
                    return
                }

                timeout?.cancel()
                completionHandler(result)
                done()
            }

            if timeoutInterval != .infinity {
                // Fires on `eventQueue`, so it can't interleave with the event handler above
                timeout = DispatchTimeout(after: timeoutInterval, on: eventQueue) { [weak self] in
                    task.cancel()

                    // CoreBluetooth keeps trying to connect indefinitely otherwise
                    self?.cancelPeripheralConnection(peripheral)
                    completionHandler(.failure(CBError(.connectionTimeout)))
                }
            }

            handle.add(task)
            if let timeout = timeout {
                handle.add(CancelTimeout(timeout))
            }

            connect(peripheral, options: options)
        }

        return handle
    }

    /// Scans for peripherals, calling `onPeripheralFound` for each advertisement received.
    ///
    /// Only one scan can be in progress at a time. Starting another scan, or calling
    /// ``stopScan()``, ends every scan currently running.
    @discardableResult
    func scanForPeripherals(withServices services: [CBUUID]? = nil, timeout timeoutInterval: TimeInterval? = nil, options: [String: Any]? = nil, onPeripheralFound: @escaping (Peripheral) -> Void) -> CancellableTask {
        eventQueue.safeSync {
            var timeout: DispatchTimeout?
            let subscription = eventSubscriptions.queue { event, done in
                switch event {
                case .discovered(let peripheral, _, _):
                    onPeripheralFound(peripheral)
                case .stopScan:
                    done()
                default:
                    break
                }
            } completion: { [weak self] in
                guard let self = self else { return }
                timeout?.cancel()
                self.centralManager.stopScan()
            }

            if let timeoutInterval = timeoutInterval, timeoutInterval != .infinity {
                timeout = DispatchTimeout(after: timeoutInterval, on: eventQueue) {
                    subscription.cancel()
                }
            }

            centralManager.scanForPeripherals(withServices: services, options: options)

            return subscription
        }
    }

    @discardableResult
    func cancelPeripheralConnection(_ peripheral: Peripheral, completionHandler: @escaping (Result<Void, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            guard isConnected(peripheral) else {
                completionHandler(.success(Void()))
                return
            }

            handle.add(eventSubscriptions.queue { event, done in
                guard case .disconnected(let disconnected, let error) = event,
                      disconnected == peripheral else { return }

                if let error = error {
                    completionHandler(.failure(error))
                } else {
                    completionHandler(.success(Void()))
                }

                done()
            })

            cancelPeripheralConnection(peripheral)
        }

        return handle
    }
}

/// Lets a ``DispatchTimeout`` be cancelled alongside the subscriptions of the operation it belongs to.
private struct CancelTimeout: CancellableTask {
    let timeout: DispatchTimeout

    init(_ timeout: DispatchTimeout) {
        self.timeout = timeout
    }

    func cancel() {
        timeout.cancel()
    }
}
