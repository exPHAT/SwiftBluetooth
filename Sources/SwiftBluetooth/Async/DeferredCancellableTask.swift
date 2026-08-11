import Foundation

/// A handle for work that hasn't been registered yet.
///
/// Operations register their subscriptions asynchronously on an event queue, so the
/// caller gets this back immediately. Cancelling it cancels whatever has been added
/// so far, and anything added afterwards is cancelled on arrival.
internal final class DeferredCancellableTask: CancellableTask {
    private let lock = NSLock()
    private var children: [CancellableTask] = []
    private var cancelled = false
    private var onCancel: (() -> Void)?

    internal var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }

        return cancelled
    }

    /// Sets the work that reports the cancellation back to whoever started the operation.
    ///
    /// Runs at most once, whether cancellation arrives before or after the operation
    /// managed to register anything, so a caller always hears that their work stopped.
    func reportCancellation(_ report: @escaping () -> Void) {
        lock.lock()
        let alreadyCancelled = cancelled
        if !alreadyCancelled {
            onCancel = report
        }
        lock.unlock()

        if alreadyCancelled {
            report()
        }
    }

    func add(_ task: CancellableTask?) {
        guard let task = task else { return }

        lock.lock()
        let alreadyCancelled = cancelled
        if !alreadyCancelled {
            children.append(task)
        }
        lock.unlock()

        if alreadyCancelled {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        let alreadyCancelled = cancelled
        cancelled = true
        let children = self.children
        self.children = []
        let onCancel = self.onCancel
        self.onCancel = nil
        lock.unlock()

        guard !alreadyCancelled else { return }

        // Cancelling runs subscription completions, so it happens outside the lock
        children.forEach { $0.cancel() }
        onCancel?()
    }
}
