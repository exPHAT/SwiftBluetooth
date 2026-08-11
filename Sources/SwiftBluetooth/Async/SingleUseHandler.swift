import Foundation

/// Delivers a result to a completion handler exactly once.
///
/// An operation can finish, time out, and be cancelled at very nearly the same moment,
/// from different queues. Whichever gets there first is the one the caller hears about,
/// and the rest are dropped.
internal final class SingleUseHandler<Success> {
    private let lock = NSLock()
    private var handler: ((Result<Success, Error>) -> Void)?

    init(_ handler: @escaping (Result<Success, Error>) -> Void) {
        self.handler = handler
    }

    /// Called as `completionHandler(result)`, so wrapping a handler doesn't change how it's used.
    func callAsFunction(_ result: Result<Success, Error>) {
        lock.lock()
        let handler = self.handler
        self.handler = nil
        lock.unlock()

        // Never call out to the handler while holding the lock
        handler?(result)
    }
}
