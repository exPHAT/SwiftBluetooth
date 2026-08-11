import Foundation

/// An error reported by ``CentralManager``.
public enum CentralManagerError: Error, Equatable, Sendable {
    /// The operation failed without CoreBluetooth telling us why.
    case unknown

    /// The app isn't allowed to use Bluetooth. This doesn't recover on its own —
    /// the person using the app has to grant permission in Settings.
    case unauthorized

    /// Bluetooth isn't supported on this device.
    case unavailable

    /// The manager didn't reach the state being waited for in time.
    case timedOut
}

extension CentralManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknown:
            return "The operation failed for an unknown reason."
        case .unauthorized:
            return "The app isn't authorized to use Bluetooth."
        case .unavailable:
            return "Bluetooth isn't available on this device."
        case .timedOut:
            return "Timed out waiting for Bluetooth to reach the expected state."
        }
    }
}

@available(*, deprecated, renamed: "CentralManagerError")
public typealias CentralError = CentralManagerError
