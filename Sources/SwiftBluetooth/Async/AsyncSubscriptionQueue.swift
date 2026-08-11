import Foundation

internal final class AsyncSubscriptionQueue<Value>: @unchecked Sendable {
    private var items: [AsyncSubscription<Value>] = []
    private let lock = NSLock()

    // Values are always delivered on this queue so subscribers observe events in the order they occurred.
    private let dispatchQueue: DispatchQueue

    internal var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }

        return items.isEmpty
    }

    init(_ dispatchQueue: DispatchQueue = .init(label: "async-subscription-queue")) {
        self.dispatchQueue = dispatchQueue
    }

    @discardableResult
    func queue(block: @escaping (Value, () -> Void) -> Void, completion: (() -> Void)? = nil) -> AsyncSubscription<Value> {
        let item = AsyncSubscription(parent: self, block: block, completion: completion)

        lock.lock()
        items.append(item)
        lock.unlock()

        return item
    }

    func receive(_ value: Value) {
        let transfer = UncheckedTransfer(value)

        dispatchQueue.async { [weak self] in
            guard let self = self else { return }

            self.lock.lock()
            let snapshot = self.items
            self.lock.unlock()

            for item in snapshot.reversed() {
                // A block earlier in this pass may have cancelled a later one
                guard self.contains(item) else { continue }

                // Never call out to subscriber code while holding the lock
                item.block(transfer.value, item.cancel)
            }
        }
    }

    @discardableResult
    func remove(_ item: AsyncSubscription<Value>) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let index = items.firstIndex(of: item) else { return false }

        items.remove(at: index)
        return true
    }

    private func contains(_ item: AsyncSubscription<Value>) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return items.contains(item)
    }
}
