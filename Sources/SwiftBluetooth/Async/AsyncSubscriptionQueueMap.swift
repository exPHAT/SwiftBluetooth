import Foundation

public class AsyncSubscriptionQueueMap<Key, Value> where Key: Hashable {
    private var items: [Key: AsyncSubscriptionQueue<Value>] = [:]

    private let dispatchQueue = DispatchQueue(label: "async-subscription-queue-map")

    @discardableResult
    func queue(key: Key, completionHandler: @escaping (Value, DoneHandler) -> Void) -> AsyncEventSubscription<Value> {
        var item: AsyncSubscriptionQueue<Value>?

        dispatchQueue.safeSync {
            item = items[key]
        }

        guard let item else {
            dispatchQueue.safeSync {
                items[key] = .init()
            }

            return queue(key: key, completionHandler: completionHandler)
        }

        return item.queue(completionHandler: completionHandler)
    }

    func recieve(key: Key, withValue value: Value) {
        dispatchQueue.async {
            guard let queue = self.items[key] else { return }

            queue.recieve(value)
        }
    }
}
