import Foundation
import CoreBluetooth

public extension CentralManager {
    func waitUntilReady() async {
        await withCheckedContinuation { cont in
            self.waitUntilReady {
                cont.resume()
            }
        }
    }

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

//    // TODO: Mark these as @available and have a non-returning version without an EventStream
    @discardableResult // Traditionally this API will not return anything
    func scanForPeripherals(withServices services: [CBUUID]? = nil, options: [String: Any]? = nil) -> AsyncStream<Peripheral> {
        .init { cont in
            let subscription = self.scanForPeripherals(withServices: services, options: options) { peripheral in
                cont.yield(peripheral)
            }

            cont.onTermination = { _ in
                subscription.cancel()
            }
        }
    }
}
