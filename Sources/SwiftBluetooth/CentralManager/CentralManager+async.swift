import Foundation
import CoreBluetooth

public extension CentralManager {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { cont in
            self.waitUntilReady { result in
                cont.resume(with: result)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    @discardableResult
    func connect(_ peripheral: Peripheral, timeout: TimeInterval, options: [String: Any]? = nil) async throws -> Peripheral {
        var cancelled = false
        var continuation: CheckedContinuation<Peripheral, Error>?
        let cancel = {
            cancelled = true
            self.cancelPeripheralConnection(peripheral)
            continuation?.resume(throwing: CancellationError())
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont

                if cancelled {
                    cancel()
                    return
                }

                self.connect(peripheral, timeout: timeout, options: options) { result in
                    guard !cancelled else { return }

                    cont.resume(with: result)
                }
            }
        } onCancel: {
            cancel()
        }
    }

    // This method doesn't need to be marked async, but it prevents a signature collision
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func scanForPeripherals(withServices services: [CBUUID]? = nil, timeout: TimeInterval? = nil, options: [String: Any]? = nil) async -> AsyncStream<Peripheral> {
        .init { cont in
            var timer: Timer?
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
                timer?.invalidate()
                self.centralManager.stopScan()
            }

            if let timeout = timeout {
                let timeoutTimer = Timer(fire: Date() + timeout, interval: 0, repeats: false) { _ in
                    subscription.cancel()
                    cont.finish()
                }
                timer = timeoutTimer
                RunLoop.main.add(timeoutTimer, forMode: .default)
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
                cont.resume(with: result)
            }
        }
    }
}
