import Foundation
import CoreBluetooth

public extension CentralManager {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func waitUntilReady() async throws {
        try await withCancellableContinuation { completion in
            self.waitUntilReady(completionHandler: completion)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func connect(_ peripheral: Peripheral, timeout: TimeInterval = .infinity, options: [String: Any]? = nil) async throws -> Peripheral {
        try await withCancellableContinuation {
            // Cancelling only stops us waiting, so the pending connection is torn down too
            self.cancelPeripheralConnection(peripheral)
        } register: { completion in
            self.connect(peripheral, timeout: timeout, options: options, completionHandler: completion)
        }
    }

    /// Scans for peripherals, yielding each one as it's discovered.
    ///
    /// Only one scan can be in progress at a time. Starting another scan, or calling
    /// ``stopScan()``, finishes every scan stream currently running.
    // This method doesn't need to be marked async, but it prevents a signature collision
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func scanForPeripherals(withServices services: [CBUUID]? = nil, timeout timeoutInterval: TimeInterval? = nil, options: [String: Any]? = nil) async -> AsyncStream<Peripheral> {
        .init { cont in
            var timeout: DispatchTimeout?
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
                timeout?.cancel()
                self.centralManager.stopScan()
            }

            if let timeoutInterval = timeoutInterval, timeoutInterval != .infinity {
                timeout = DispatchTimeout(after: timeoutInterval, on: eventQueue) {
                    subscription.cancel()
                    cont.finish()
                }
            }

            cont.onTermination = { _ in
                subscription.cancel()
            }

            centralManager.scanForPeripherals(withServices: services, options: options)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func cancelPeripheralConnection(_ peripheral: Peripheral) async throws {
        try await withCancellableContinuation { completion in
            self.cancelPeripheralConnection(peripheral, completionHandler: completion)
        }
    }
}
