import Foundation

internal final class AsyncSubscriptionQueueMap<Key, Value> where Key: Hashable {
    private var items: [Key: AsyncSubscriptionQueue<Value>] = [:]
    private let lock = NSLock()

    private let dispatchQueue: DispatchQueue

    internal var isEmpty: Bool {
        lock.lock()
        let queues = Array(items.values)
        lock.unlock()

        return queues.allSatisfy { $0.isEmpty }
    }

    init(_ dispatchQueue: DispatchQueue = .init(label: "async-subscription-queue-map")) {
        self.dispatchQueue = dispatchQueue
    }

    @discardableResult
    func queue(key: Key, block: @escaping (Value, () -> Void) -> Void, completion: (() -> Void)? = nil) -> AsyncSubscription<Value> {
        lock.lock()
        let queue: AsyncSubscriptionQueue<Value>
        if let existing = items[key] {
            queue = existing
        } else {
            queue = .init(dispatchQueue)
            items[key] = queue
        }
        lock.unlock()

        return queue.queue(block: block, completion: completion)
    }

    func receive(key: Key, withValue value: Value) {
        lock.lock()
        let queue = items[key]
        lock.unlock()

        queue?.receive(value)
    }
}
