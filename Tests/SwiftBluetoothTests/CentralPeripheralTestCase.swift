import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

class CentralPeripheralTestCase: XCTestCase {
    var central: CentralManager!
    var peripheral: Peripheral!
    
    override func setUp() {
        mockPeripheral.connectionDelegate?.reset()
        CBMCentralManagerMock.simulatePeripherals([mockPeripheral])
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        central = CentralManager()
    }

    override func tearDown() async throws {
        var hadPeripheral = false

        if let peripheral {
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

            if mockPeripheral.isConnected {
                try await central.cancelPeripheralConnection(peripheral)
            }

            peripheral = nil

            if weakPeripheral != nil {
                DispatchQueue.main.sync { }
            }

            XCTAssertNil(weakPeripheral)
        }

        peripheral = nil
        central = nil
        DispatchQueue.main.sync { }
        XCTAssertNil(weakCentral)

        CBMCentralManagerMock.tearDownSimulation()
    }
}
