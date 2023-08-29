import Foundation

public class AsyncSubscriptionQueue<Value> {
    private var items: [AsyncEventSubscription<Value>] = []

    @discardableResult
    func queue(completionHandler: @escaping (Value, DoneHandler) -> Void) -> AsyncEventSubscription<Value> {
        let item = AsyncEventSubscription(parent: self, completionHandler: completionHandler)
        items.append(item)

        return item
    }

    func recieve(_ value: Value) {
        for item in items.reversed() {
            let doneHandler: () -> Void = {
                self.remove(item)
            }

            item.completionHandler(value, doneHandler)
        }
    }

    func remove(_ item: AsyncEventSubscription<Value>) {
        items.removeAll(where: { $0 == item })
    }
}
