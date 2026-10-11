import Foundation
@preconcurrency import CoreBluetooth

public extension CentralManager {
    /// Waits until the manager reaches a given state, calling `completionHandler` when it does.
    ///
    /// Returns straight away if the manager is already in that state.
    ///
    /// Some states can't be recovered from — the app not being allowed to use Bluetooth, or the
    /// device not supporting it — so reaching one of those fails instead of waiting forever.
    /// Waiting for one of them on purpose still succeeds.
    ///
    /// - Parameters:
    ///   - state: The state to wait for.
    ///   - timeoutInterval: How long to wait before giving up. Waits indefinitely by default.
    ///   - completionHandler: Called once the state is reached, or with the reason it wasn't.
    @discardableResult
    func wait(for state: CBManagerState, timeout timeoutInterval: TimeInterval = .infinity, completionHandler: @escaping (Result<Void, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()
        let completionHandler = SingleUseHandler(completionHandler)

        // Reported whether cancellation lands before or after the work is registered
        handle.reportCancellation { completionHandler(.failure(CancellationError())) }

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            if let result = Self.result(reaching: self.state, whileWaitingFor: state) {
                completionHandler(result)
                return
            }

            var timeout: DispatchTimeout?

            let subscription = eventSubscriptions.queue { event, done in
                guard case .stateUpdated(let updated) = event,
                      let result = Self.result(reaching: updated, whileWaitingFor: state) else { return }

                timeout?.cancel()
                completionHandler(result)
                done()
            }

            if timeoutInterval != .infinity {
                // Fires on `eventQueue`, so it can't interleave with the handler above
                let timeoutToken = DispatchTimeout(after: timeoutInterval, on: eventQueue) {
                    subscription.cancel()
                    completionHandler(.failure(CentralManagerError.timedOut))
                }

                timeout = timeoutToken
                handle.add(CancelTimeout(timeoutToken))
            }

            handle.add(subscription)
        }

        return handle
    }

    @available(*, deprecated, message: "Use wait(for: .poweredOn, completionHandler:) instead.")
    @discardableResult
    func waitUntilReady(completionHandler: @escaping (Result<Void, Error>) -> Void) -> CancellableTask {
        wait(for: .poweredOn, completionHandler: completionHandler)
    }

    /// The outcome of arriving at `state` while waiting for `wanted`, or `nil` to keep waiting.
    private static func result(reaching state: CBManagerState, whileWaitingFor wanted: CBManagerState) -> Result<Void, Error>? {
        guard state != wanted else { return .success(Void()) }

        switch state {
        case .unauthorized:
            return .failure(CentralManagerError.unauthorized)
        case .unsupported:
            return .failure(CentralManagerError.unavailable)
        default:
            return nil
        }
    }

    /// Connects to a peripheral, reporting the outcome to `completionHandler`.
    ///
    /// With the default infinite timeout the request stays with CoreBluetooth until it
    /// produces an outcome. Cancelling the returned task only stops the completion handler
    /// from being called — the pending request itself is left in place, making this the
    /// completion-handler form of ``connectPersistently(_:options:)``. The `async` form
    /// behaves differently: cancelling its task tears the pending request down, because a
    /// call that has thrown `CancellationError` must not be followed by a connection nobody
    /// is waiting for.
    @discardableResult
    func connect(_ peripheral: Peripheral, timeout timeoutInterval: TimeInterval = .infinity, options: [String: Any]? = nil, completionHandler: @escaping (Result<Peripheral, Error>) -> Void) -> CancellableTask {
        let handle = DeferredCancellableTask()
        let completionHandler = SingleUseHandler(completionHandler)
        let options = UncheckedTransfer(options)

        // Reported whether cancellation lands before or after the work is registered
        handle.reportCancellation { completionHandler(.failure(CancellationError())) }

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
                    result = .failure(error ?? CentralManagerError.unknown)
                case .failToConnect(let failed, let error):
                    guard failed == peripheral else { return }
                    result = .failure(error ?? CentralManagerError.unknown)
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

            connect(peripheral, options: options.value)
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
        let completionHandler = SingleUseHandler(completionHandler)

        // Reported whether cancellation lands before or after the work is registered
        handle.reportCancellation { completionHandler(.failure(CancellationError())) }

        eventQueue.async { [self] in
            guard !handle.isCancelled else { return }

            // A restored or retrieved peripheral can be connected without this manager ever
            // seeing a `didConnect`, so the peripheral's own state decides whether a
            // disconnection is coming. When neither side thinks it's connected, ask
            // CoreBluetooth anyway: cancelling is also how a pending connection request is
            // torn down, and nothing is reported back for that.
            guard peripheral.state == .connected || isConnected(peripheral) else {
                cancelPeripheralConnection(peripheral)

                // Tearing down a pending request reports nothing, so anything waiting on
                // this peripheral's connection has to be finished off here — otherwise an
                // in-flight `connect` with the default infinite timeout waits forever on
                // an event CoreBluetooth will never send.
                eventSubscriptions.receive(.disconnected(peripheral, CBError(.peripheralDisconnected)))

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
