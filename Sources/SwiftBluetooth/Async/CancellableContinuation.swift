import Foundation

/// Bridges a completion-handler API to `async`, resuming the continuation exactly once
/// and cancelling the underlying operation when the surrounding task is cancelled.
///
/// - Parameters:
///   - onCancel: extra work to perform when the task is cancelled, beyond cancelling
///     the registered operation.
///   - register: starts the operation, returning a handle used to cancel it. The
///     completion may be called more than once — every call after the first is ignored.
@available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
internal func withCancellableContinuation<T>(
    onCancel: (() -> Void)? = nil,
    register: (@escaping (Result<T, Error>) -> Void) -> CancellableTask
) async throws -> T {
    let state = CancellableContinuationState<T>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            // Already cancelled, so the operation is never started
            guard state.bind(continuation) else { return }

            state.attach(register { result in
                state.resume(result)
            })
        }
    } onCancel: {
        state.cancel(performing: onCancel)
    }
}

/// Resume-once state machine shared between the continuation, the operation's
/// completion handler, and the cancellation handler, which all run on different threads.
///
/// Continuations are resumed and tasks cancelled outside the lock.
@available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
private final class CancellableContinuationState<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var attached: CancellableTask?
    private var finished = false
    private var cancelled = false

    /// Returns whether the operation should be started.
    func bind(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()

        guard !cancelled, !finished else {
            finished = true
            lock.unlock()

            continuation.resume(throwing: CancellationError())
            return false
        }

        self.continuation = continuation
        lock.unlock()

        return true
    }

    func attach(_ task: CancellableTask) {
        lock.lock()
        let alreadyDone = finished || cancelled
        if !alreadyDone {
            attached = task
        }
        lock.unlock()

        if alreadyDone {
            task.cancel()
        }
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()

        guard !finished, let continuation = continuation else {
            lock.unlock()
            return
        }

        finished = true
        self.continuation = nil
        attached = nil
        lock.unlock()

        continuation.resume(with: result)
    }

    func cancel(performing extraWork: (() -> Void)?) {
        lock.lock()
        cancelled = true

        guard !finished else {
            lock.unlock()
            return
        }

        // When the task is cancelled before the continuation exists, `bind` throws instead
        let continuation = self.continuation
        if continuation != nil {
            finished = true
            self.continuation = nil
        }

        let attached = self.attached
        self.attached = nil
        lock.unlock()

        attached?.cancel()
        extraWork?()
        continuation?.resume(throwing: CancellationError())
    }
}
