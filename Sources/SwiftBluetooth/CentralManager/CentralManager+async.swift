import Foundation
@preconcurrency import CoreBluetooth

public extension CentralManager {
    /// Waits until the manager reaches a given state.
    ///
    /// Returns straight away if the manager is already in that state.
    ///
    /// Some states can't be recovered from — the app not being allowed to use Bluetooth, or the
    /// device not supporting it — so reaching one of those throws instead of waiting forever.
    /// Waiting for one of them on purpose still succeeds.
    ///
    /// - Parameters:
    ///   - state: The state to wait for.
    ///   - timeout: How long to wait before giving up. Waits indefinitely by default.
    func wait(for state: CBManagerState, timeout: TimeInterval = .infinity) async throws {
        try await withCancellableContinuation { completion in
            self.wait(for: state, timeout: timeout, completionHandler: completion)
        }
    }

    @available(*, deprecated, message: "Use wait(for: .poweredOn) instead.")
    func waitUntilReady() async throws {
        try await wait(for: .poweredOn)
    }

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
    ///
    /// The stream finishes normally when scanning stops or the timeout elapses, and throws
    /// if the manager can no longer scan — Bluetooth being switched off, for instance.
    // This method doesn't need to be marked async, but it prevents a signature collision
    func scanForPeripherals(withServices services: [CBUUID]? = nil, timeout timeoutInterval: TimeInterval? = nil, options: [String: Any]? = nil) async -> AsyncThrowingStream<Peripheral, Error> {
        .init { cont in
            var timeout: DispatchTimeout?
            let subscription = eventSubscriptions.queue { event, done in
                switch event {
                case .discovered(let peripheral, _, _):
                    cont.yield(peripheral)
                case .stopScan(let error):
                    done()
                    cont.finish(throwing: error)
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

    func cancelPeripheralConnection(_ peripheral: Peripheral) async throws {
        try await withCancellableContinuation { completion in
            self.cancelPeripheralConnection(peripheral, completionHandler: completion)
        }
    }
}
