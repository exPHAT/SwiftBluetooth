import Foundation

internal final class AsyncSubscriptionQueue<Value> {
    private var items: [AsyncSubscription<Value>] = []

    private lazy var dispatchQueue = DispatchQueue(label: "async-subscription-queue")

    @discardableResult
    func queue(completionHandler: @escaping (Value, () -> Void) -> Void) -> AsyncSubscription<Value> {
        let item = AsyncSubscription(parent: self, completionHandler: completionHandler)

        dispatchQueue.async {
            self.items.append(item)
        }

        return item
    }

    func recieve(_ value: Value) {
        dispatchQueue.async {
            for item in self.items.reversed() {
                let doneHandler: () -> Void = {
                    self.remove(item)
                }

//                DispatchQueue.main.async {
                    item.completionHandler(value, doneHandler)
//                }
            }
        }
    }

    func remove(_ item: AsyncSubscription<Value>) {
        dispatchQueue.safeSync {
            self.items.removeAll(where: { $0 == item })
        }
    }
}

