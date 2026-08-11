import Foundation

/// A one-shot timeout that fires on a given queue.
///
/// Firing on the same queue the events are delivered on means a timeout can never
/// overlap with the event it's racing: whichever runs first cancels the other.
internal final class DispatchTimeout: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?

    init(after interval: TimeInterval, on queue: DispatchQueue, handler: @escaping () -> Void) {
        self.handler = handler

        // Held strongly until the deadline so the timeout still fires when the
        // caller doesn't keep a reference to it
        queue.asyncAfter(deadline: Self.deadline(after: interval)) {
            self.lock.lock()
            let handler = self.handler
            self.handler = nil
            self.lock.unlock()

            handler?()
        }
    }

    /// Prevents the timeout from firing. Safe to call more than once, and from any thread.
    func cancel() {
        lock.lock()
        // Dropping the handler here also releases whatever it captured, rather than
        // holding onto it until the deadline passes
        handler = nil
        lock.unlock()
    }

    private static func deadline(after interval: TimeInterval) -> DispatchTime {
        // `.now() + interval` traps on values that don't fit in nanoseconds
        guard interval.isFinite, interval < TimeInterval(UInt64.max / NSEC_PER_SEC) else { return .distantFuture }

        return .now() + interval
    }
}
