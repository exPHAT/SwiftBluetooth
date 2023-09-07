import Foundation

// https://stackoverflow.com/a/57075142
extension DispatchQueue {
    private static let idKey = DispatchSpecificKey<Int>()

    var id: Int {
        let value = unsafeBitCast(self, to: Int.self)
        setSpecific(key: Self.idKey, value: value)
        return value
    }

    /// Checks if this queue is the place of execution.
    var isCurrent: Bool {
        id == DispatchQueue.getSpecific(key: Self.idKey)
    }

    /// Performs synchronized execution avoiding deadlocks.
    func safeSync<T>(flags: DispatchWorkItemFlags? = nil, execute block: () throws -> T) rethrows -> T {
        try isCurrent ? block() : sync(flags: flags ?? [], execute: block)
    }
}
