import Foundation

internal final class AsyncSubscriptionQueueMap<Key, Value> where Key: Hashable {
    private var items: [Key: AsyncSubscriptionQueue<Value>] = [:]

    internal var isEmpty: Bool {
        items.values.allSatisfy { $0.isEmpty }
    }

    // TODO: Convert these to just use a lock
    private let dispatchQueue: DispatchQueue

    init(_ dispatchQueue: DispatchQueue = .init(label: "async-subscription-queue-map")) {
        self.dispatchQueue = dispatchQueue
    }

    @discardableResult
    func queue(key: Key, block: @escaping (Value, () -> Void) -> Void, completion: (() -> Void)? = nil) -> AsyncSubscription<Value> {
        var item: AsyncSubscriptionQueue<Value>?

        dispatchQueue.safeSync {
            item = items[key]
        }

        guard let item = item else {
            dispatchQueue.safeSync {
                items[key] = .init(self.dispatchQueue)
            }

            return queue(key: key, block: block, completion: completion)
        }

        return item.queue(block: block, completion: completion)
    }

    func recieve(key: Key, withValue value: Value) {
        dispatchQueue.async {
            guard let queue = self.items[key] else { return }

            queue.receive(value)
        }
    }
}
