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

    internal var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }

        return cancelled
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
        cancelled = true
        let children = self.children
        self.children = []
        lock.unlock()

        // Cancelling runs subscription completions, so it happens outside the lock
        children.forEach { $0.cancel() }
    }
}
