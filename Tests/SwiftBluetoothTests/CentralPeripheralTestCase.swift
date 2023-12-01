import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

class CentralPeripheralTestCase: XCTestCase {
    let connectionTimeout: TimeInterval = 2

    var central: CentralManager!
    var peripheral: Peripheral!

    override func setUp() {
        mockPeripheral.connectionDelegate?.reset()
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        CBMCentralManagerMock.simulatePeripherals([mockPeripheral])
        mockPeripheral.simulateProximityChange(.near)
        central = CentralManager()
    }

    override func tearDown() async throws {
        var hadPeripheral = false

        if let peripheral {
            if mockPeripheral.isConnected {
                try await central.cancelPeripheralConnection(peripheral)
            }
            central.removePeripheral(peripheral.cbPeripheral)
            DispatchQueue.main.sync { }

            hadPeripheral = true

            XCTAssertTrue(peripheral.responseMap.isEmpty)
            XCTAssertTrue(peripheral.writeMap.isEmpty)
            XCTAssertTrue(peripheral.descriptorMap.isEmpty)
            XCTAssertTrue(peripheral.eventSubscriptions.isEmpty)
        }

        XCTAssertTrue(central.eventSubscriptions.isEmpty)

        weak var weakCentral = central

        if hadPeripheral {
            weak var weakPeripheral = peripheral

            peripheral = nil

            if weakPeripheral != nil {
                XCTFail("Peripheral is being retained")
            }
        }

        peripheral = nil
        central = nil
        DispatchQueue.main.sync { }
        XCTAssertNil(weakCentral)

        CBMCentralManagerMock.tearDownSimulation()
    }
}
