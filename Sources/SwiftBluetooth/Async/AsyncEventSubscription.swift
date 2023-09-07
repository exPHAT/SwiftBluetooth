import Foundation

public typealias DoneHandler = () -> Void

public struct AsyncEventSubscription<Value>: Identifiable, Equatable {
    public let id = UUID()
    weak var parent: AsyncSubscriptionQueue<Value>?
    let completionHandler: (Value, DoneHandler) -> Void

    internal func cancel() {
        parent?.remove(self)
    }

    // MARK: - Equatable conformance
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
