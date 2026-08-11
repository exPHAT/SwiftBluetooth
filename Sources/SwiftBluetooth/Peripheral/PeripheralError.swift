import Foundation

public enum PeripheralError: Error {
    case unknown

    /// A ``Characteristic`` was used before it had been discovered on this peripheral.
    /// Call `discoverCharacteristics` first.
    case characteristicNotFound
}
