import Foundation
@preconcurrency import CoreBluetooth

/// A characteristic identified by UUID, so you don't have to keep `CBCharacteristic`
/// instances around your app.
///
/// Define the ones you use as static properties, then pass them anywhere a characteristic
/// is expected:
///
/// ```swift
/// extension Characteristic {
///     static let someCharacteristic = Self("00000000-0000-0000-0000-000000000000")
/// }
///
/// let value = try await peripheral.readValue(for: .someCharacteristic)
/// ```
///
/// A characteristic has to be discovered on the peripheral before it can be used. Using one
/// that hasn't been reports ``PeripheralError/characteristicNotFound``.
public struct Characteristic: Hashable, Equatable, ExpressibleByStringLiteral, Sendable {
    public var uuid: CBUUID

    /// Creates a characteristic from a UUID string.
    public init(_ uuidString: String) {
        self.uuid = .init(string: uuidString)
    }

    /// Creates a characteristic from an existing `CBUUID`.
    public init(cbUuid: CBUUID) {
        self.uuid = cbUuid
    }

    public init(stringLiteral value: StringLiteralType) {
        self.uuid = .init(string: value)
    }
}
