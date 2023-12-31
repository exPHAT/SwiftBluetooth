import Foundation
import CoreBluetooth

public extension CentralManager {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func waitUntilReady() async {
        await withCheckedContinuation { cont in
            self.waitUntilReady {
                cont.resume()
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func connect(_ peripheral: Peripheral, options: [String: Any]? = nil) async throws -> Peripheral {
        try await withCheckedThrowingContinuation { cont in
            self.connect(peripheral, options: options) { result in
                switch result {
                case .success(let peripheral):
                    cont.resume(returning: peripheral)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // This method doesn't need to be marked async, but it prevents a signature collision
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func scanForPeripherals(withServices services: [CBUUID]? = nil, options: [String: Any]? = nil) async -> AsyncStream<Peripheral> {
        .init { cont in
            let subscription = eventSubscriptions.queue { event, done in
                switch event {
                case .discovered(let peripheral, _, _):
                    cont.yield(peripheral)
                case .stopScan:
                    done()
                    cont.finish()
                default:
                    break
                }
            } completion: { [weak self] in
                guard let self = self else { return }
                self.centralManager.stopScan()
            }

            cont.onTermination = { _ in
                subscription.cancel()
            }


            centralManager.scanForPeripherals(withServices: services, options: options)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func cancelPeripheralConnection(_ peripheral: Peripheral) async throws {
        try await withCheckedThrowingContinuation { cont in
            self.cancelPeripheralConnection(peripheral) { result in
                switch result {
                case .success(_):
                    cont.resume()
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }

    }
}
