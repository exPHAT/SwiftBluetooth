import Foundation

public typealias DoneHandler = () -> Void

internal struct AsyncEventSubscription<Value>: Identifiable, Equatable, CancellableTask {
    public let id = UUID()
    weak var parent: AsyncSubscriptionQueue<Value>?
    let completionHandler: (Value, DoneHandler) -> Void

    public func cancel() {
        parent?.remove(self)
    }

    // MARK: - Equatable conformance
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
