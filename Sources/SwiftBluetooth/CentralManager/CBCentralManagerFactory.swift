import Foundation
import CoreBluetooth

// This is used to match CoreBluetoothMocks factory.
// This file is ignored by the Package.swift when SwiftBluetoothMock is used.
enum CBCentralManagerFactory {
    static func instance(delegate: CBCentralManagerDelegate? = nil, queue: DispatchQueue? = nil, options: [String: Any]? = nil, forceMock: Bool) -> CBCentralManager {
        return CBCentralManager(delegate: delegate, queue: queue, options: options)
    }
}
