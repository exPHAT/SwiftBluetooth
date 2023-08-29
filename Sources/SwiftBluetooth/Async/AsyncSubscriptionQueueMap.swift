import Foundation

public class AsyncSubscriptionQueueMap<Key, Value> where Key: Hashable {
    private var items: [Key: AsyncSubscriptionQueue<Value>] = [:]

    @discardableResult
    func queue(key: Key, completionHandler: @escaping (Value, DoneHandler) -> Void) -> AsyncEventSubscription<Value> {
        guard let queue = items[key] else {
            items[key] = .init()
            return queue(key: key, completionHandler: completionHandler)
        }

        return queue.queue(completionHandler: completionHandler)
    }

    func recieve(key: Key, withValue value: Value) {
        guard let queue = items[key] else { return }

        queue.recieve(value)
    }
}
