import Foundation

/// Carries a value to whoever picks it up next, across a boundary the compiler can't check.
///
/// Events and their payloads are handed between CoreBluetooth's queue, this library's event
/// queues, and the tasks waiting on them. CoreBluetooth's types aren't `Sendable`, and neither
/// is a `[String: Any]` of advertisement data, so every one of those handovers is unchecked.
///
/// What makes them safe is that each value is passed on and not touched again: the queues are
/// serial, so exactly one place is reading a value at a time.
internal struct UncheckedTransfer<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
