import Foundation

internal final class AsyncSubscriptionQueue<Value> {
    private var items: [AsyncSubscription<Value>] = []

    internal var isEmpty: Bool {
        items.isEmpty
    }

    // TODO: Convert these to just use a lock
    private let dispatchQueue: DispatchQueue

    init(_ dispatchQueue: DispatchQueue = .init(label: "async-subscription-queue")) {
        self.dispatchQueue = dispatchQueue
    }

    @discardableResult
    func queue(block: @escaping (Value, () -> Void) -> Void, completion: (() -> Void)? = nil) -> AsyncSubscription<Value> {
        let item = AsyncSubscription(parent: self, block: block, completion: completion)

        dispatchQueue.async {
            self.items.append(item)
        }

        return item
    }

    func recieve(_ value: Value) {
        dispatchQueue.async {
            for item in self.items.reversed() {
                item.block(value, item.cancel)
            }
        }
    }

    func remove(_ item: AsyncSubscription<Value>) {
        dispatchQueue.safeSync {
            self.items.removeAll(where: { $0 == item })
        }
    }
}
