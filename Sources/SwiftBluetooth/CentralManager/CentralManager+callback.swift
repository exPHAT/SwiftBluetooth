import Foundation
import CoreBluetooth

public extension CentralManager {
    func waitUntilReady(completionHandler: @escaping () -> Void) {
        eventQueue.sync {
            guard state != .poweredOn else {
                completionHandler()
                return
            }

            eventSubscriptions.queue { event, done in
                guard case .stateUpdated(let state) = event,
                      state == .poweredOn else { return }

                completionHandler()
                done()
            }
        }
    }

    func connect(_ peripheral: Peripheral, timeout: TimeInterval, options: [String: Any]? = nil, completionHandler: @escaping (Result<Peripheral, Error>) -> Void) {
        eventQueue.sync {
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

            let timeoutTimer = Timer(fire: Date() + timeout, interval: 0, repeats: false) { _ in
                task.cancel()
                completionHandler(.failure(CBError(.connectionTimeout)))
            }
            timer = timeoutTimer
            RunLoop.main.add(timeoutTimer, forMode: .default)

            connect(peripheral, options: options)
        }
    }

    func scanForPeripherals(withServices services: [CBUUID]? = nil, timeout: TimeInterval? = nil, options: [String: Any]? = nil, onPeripheralFound: @escaping (Peripheral) -> Void) -> CancellableTask {
        eventQueue.sync {
            var timer: Timer?
            let subscription = eventSubscriptions.queue { event, done in
                switch event {
                case .discovered(let peripheral, _, _):
                    onPeripheralFound(peripheral)
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

            if let timeout = timeout {
                let timeoutTimer = Timer(fire: Date() + timeout, interval: 0, repeats: false) { _ in
                    subscription.cancel()
                }
                timer = timeoutTimer
                RunLoop.main.add(timeoutTimer, forMode: .default)
            }

            centralManager.scanForPeripherals(withServices: services, options: options)

            return subscription
        }
    }

    func cancelPeripheralConnection(_ peripheral: Peripheral, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        eventQueue.sync {
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
