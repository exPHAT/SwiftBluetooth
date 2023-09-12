import Foundation

internal final class NotifyingTracker<Key> where Key: Hashable {
    private var external: [Key: Bool] = [:]
    private var `internal`: [Key: Int] = [:]

    let lock = NSLock()

    func setExternal(_ value: Bool, forKey key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        external[key] = value

        return value || (`internal`[key] ?? 0) > 0
    }

    func addInternal(forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }

        `internal`[key] = (`internal`[key] ?? 0) + 1
    }

    func removeInternal(forKey key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var result = (`internal`[key] ?? 0) - 1
        if result < 0 {
            result = 0
        }

        `internal`[key] = result

        // Return true when at least 1 internal characteristic is notifying
        // OR: externally, the last value for notifying was `true`
        return (result > 0) || (external[key] ?? false)
    }
}
