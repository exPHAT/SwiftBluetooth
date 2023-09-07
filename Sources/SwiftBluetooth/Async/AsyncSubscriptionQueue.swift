import Foundation

public class AsyncSubscriptionQueue<Value> {
    private var items: [AsyncEventSubscription<Value>] = []

    private lazy var dispatchQueue = DispatchQueue(label: "async-subscription-queue")

    @discardableResult
    func queue(completionHandler: @escaping (Value, DoneHandler) -> Void) -> AsyncEventSubscription<Value> {
        let item = AsyncEventSubscription(parent: self, completionHandler: completionHandler)

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

    func remove(_ item: AsyncEventSubscription<Value>) {
        dispatchQueue.safeSync {
            self.items.removeAll(where: { $0 == item })
        }
    }
}

