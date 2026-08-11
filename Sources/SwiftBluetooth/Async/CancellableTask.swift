import Foundation

/// A handle to work that can be stopped before it finishes.
///
/// Cancelling is safe from any thread, and safe to do more than once.
public protocol CancellableTask: Sendable {
    func cancel()
}
