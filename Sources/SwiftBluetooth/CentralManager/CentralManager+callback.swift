import Foundation
import CoreBluetooth

public struct PeripheralScanResult {
    public let peripheral: Peripheral
    public let advertisementData: [String: Any]
    public let rssi: NSNumber
}

public extension CentralManager {
    func waitUntilReady(timeout: TimeInterval, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        eventQueue.async { [self] in
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
            
            var timer: Timer?
            let task = eventSubscriptions.queue { event, done in
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
                
                timer?.invalidate()
                done()
            }
            
            if timeout != .infinity {
                let timeoutTimer = Timer(fire: Date() + timeout, interval: 0, repeats: false) { _ in
                    task.cancel()
                    completionHandler(.failure(CBError(.connectionTimeout)))
                }
                timer = timeoutTimer
                RunLoop.main.add(timeoutTimer, forMode: .default)
            }
        }
    }

    func connect(_ peripheral: Peripheral, timeout: TimeInterval, options: [String: Any]? = nil, completionHandler: @escaping (Result<Peripheral, Error>) -> Void) {
        eventQueue.async { [self] in
            guard peripheral.state != .connected else {
                completionHandler(.success(peripheral))
                return
            }

            var timer: Timer?
            let task = eventSubscriptions.queue { event, done in
                switch event {
                case .connected(let connected):
                    guard connected == peripheral else { return }
                    completionHandler(.success(peripheral))
                case .disconnected(let disconnected, let error):
                    guard disconnected == peripheral else { return }
                    completionHandler(.failure(error ?? CentralError.unknown))
                case .failToConnect(let failed, let error):
                    guard failed == peripheral else { return }
                    completionHandler(.failure(error ?? CentralError.unknown))
                default:
                    return
                }

                timer?.invalidate()
                done()
            }

            if timeout != .infinity {
                let timeoutTimer = Timer(fire: Date() + timeout, interval: 0, repeats: false) { _ in
                    task.cancel()
                    completionHandler(.failure(CBError(.connectionTimeout)))
                }
                timer = timeoutTimer
                RunLoop.main.add(timeoutTimer, forMode: .default)
            }

            connect(peripheral, options: options)
        }
    }

    func scanForPeripherals(withServices services: [CBUUID]? = nil, timeout: TimeInterval? = nil, options: [String: Any]? = nil, onPeripheralFound: @escaping (PeripheralScanResult) -> Void) -> CancellableTask {
        eventQueue.sync {
            var timer: Timer?
            let subscription = eventSubscriptions.queue { event, done in
                switch event {
                case .discovered(let peripheral, let advData, let rssi):
                    onPeripheralFound(PeripheralScanResult(peripheral: peripheral, advertisementData: advData, rssi: rssi))
                case .stopScan:
                    done()
                default:
                    break
                }
            } completion: { [weak self, timer] in
                guard let self = self else { return }
                timer?.invalidate()
                self.centralManager.stopScan()
            }

            if timeout != .infinity {
                if let timeout = timeout {
                    let timeoutTimer = Timer(fire: Date() + timeout, interval: 0, repeats: false) { _ in
                        subscription.cancel()
                    }
                    timer = timeoutTimer
                    RunLoop.main.add(timeoutTimer, forMode: .default)
                }
            }

            centralManager.scanForPeripherals(withServices: services, options: options)

            return subscription
        }
    }

    func cancelPeripheralConnection(_ peripheral: Peripheral, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        eventQueue.async { [self] in
            guard connectedPeripherals.contains(peripheral) else {
                completionHandler(.success(Void()))
                return
            }

            eventSubscriptions.queue { event, done in
                guard case .disconnected(let disconnected, let error) = event,
                      disconnected == peripheral else { return }

                if let error = error {
                    completionHandler(.failure(error))
                } else {
                    completionHandler(.success(Void()))
                }

                done()
            }

            cancelPeripheralConnection(peripheral)
        }
    }
}
