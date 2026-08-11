import Foundation

/// An error reported by ``Peripheral``.
public enum PeripheralError: Error, Equatable, Sendable {
    /// The operation failed without CoreBluetooth telling us why.
    case unknown

    /// A ``Characteristic`` was used before it had been discovered on this peripheral.
    /// Call `discoverCharacteristics` first.
    case characteristicNotFound
}

extension PeripheralError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknown:
            return "The operation failed for an unknown reason."
        case .characteristicNotFound:
            return "The characteristic hasn't been discovered on this peripheral yet."
        }
    }
}
