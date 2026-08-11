import Foundation

internal struct AsyncSubscription<Value>: Identifiable, Equatable, CancellableTask {
    public let id = UUID()
    weak var parent: AsyncSubscriptionQueue<Value>?
    let block: (Value, () -> Void) -> Void
    let completion: (() -> Void)?

    public func cancel() {
        // Only the call that actually removes the subscription runs the completion,
        // so cancelling more than once has no additional effect
        guard parent?.remove(self) == true else { return }

        completion?()
    }

    // MARK: - Equatable conformance
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
