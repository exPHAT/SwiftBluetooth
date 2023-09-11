import Foundation

internal struct AsyncSubscription<Value>: Identifiable, Equatable, CancellableTask {
    public let id = UUID()
    weak var parent: AsyncSubscriptionQueue<Value>?
    let block: (Value, () -> Void) -> Void
    let completion: (() -> Void)?

    public func cancel() {
        parent?.remove(self)
        completion?()
    }

    // MARK: - Equatable conformance
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
