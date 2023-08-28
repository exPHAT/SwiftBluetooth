import Foundation

struct AsyncResponse<Value>: Identifiable, Equatable {
    static func == (lhs: AsyncResponse<Value>, rhs: AsyncResponse<Value>) -> Bool {
        lhs.id == rhs.id
    }

    let id = UUID()

    let singleUse: Bool
    let completionHandler: (Value) -> Void
}

class AsyncResponseMap<Key, Value> where Key: Hashable {
    private var items: [Key: [AsyncResponse<Value>]] = [:]

    func request(key: Key, singleUse: Bool = true, completionHandler: @escaping (Value) -> Void) {
        let response = AsyncResponse(singleUse: singleUse, completionHandler: completionHandler)

        if items[key] == nil {
            items[key] = []
        }

        items[key]?.append(.init(singleUse: singleUse, completionHandler: completionHandler))
    }

    func resolve(key: Key, withValue value: Value) {
        guard let handlers = items[key] else { return }

        for handler in handlers {
            handler.completionHandler(value)
        }

        items[key]?.removeAll(where: { $0.singleUse })
    }
}
