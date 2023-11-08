import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

final class DisconnectedPeripheralTests: XCTestCase {
    var central: CentralManager!
    var peripheral: Peripheral!

    override func setUp() {
        mockPeripheral.connectionDelegate?.reset()
        CBMCentralManagerMock.simulatePeripherals([mockPeripheral])
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        central = CentralManager()
    }

    override func tearDown() {
        XCTAssertTrue(peripheral.responseMap.isEmpty)
        XCTAssertTrue(peripheral.writeMap.isEmpty)
        XCTAssertTrue(peripheral.descriptorMap.isEmpty)
        XCTAssertTrue(peripheral.eventSubscriptions.isEmpty)

        XCTAssertTrue(central.eventSubscriptions.isEmpty)

        central = nil
        peripheral = nil
        CBMCentralManagerMock.tearDownSimulation()
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadValueOnDisconnectedPeripheral() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral)
            let services = try await peripheral.discoverServices()

            var characteristics: [CBCharacteristic] = []

            for service in services {
                characteristics.append(contentsOf: try await peripheral.discoverCharacteristics(for: service))
            }

            let readableMockCharacteristic = mockCharacteristics.first(where: { $0.properties.contains(.read) })!
            let characteristic = characteristics.first(where: { $0.uuid == readableMockCharacteristic.uuid })

            XCTAssertNotNil(characteristic)

            guard let characteristic = characteristic else { fatalError() }

            XCTAssertNil(characteristic.value)

            try await central.cancelPeripheralConnection(peripheral)

            XCTAssertTrue(peripheral.state == .disconnected)
            XCTAssertFalse(mockPeripheral.isConnected)

            do {
                let _ = try await peripheral.readValue(for: characteristic)
                XCTFail("Failed to error when reading value")
            } catch {
                let cbError = error as? CBError
                XCTAssertNotNil(cbError)
                XCTAssertEqual(cbError?.code, CBError.peripheralDisconnected)
            }

        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testSetNotifyOnDisconnectedPeripheral() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral)

            XCTAssertTrue(mockPeripheral.isConnected)

            let services = try await peripheral.discoverServices()

            XCTAssertGreaterThan(services.count, 0)

            let characteristics = try await peripheral.discoverCharacteristics(for: services[0])

            XCTAssertGreaterThan(characteristics.count, 0)

            let first = characteristics[0]

            try await central.cancelPeripheralConnection(peripheral)

            do {
                try await peripheral.setNotifyValue(true, for: first)
                XCTFail("Failed to error when setting notify value")
            } catch {
                let cbError = error as? CBError
                XCTAssertNotNil(cbError)
                XCTAssertEqual(cbError?.code, CBError.peripheralDisconnected)
            }

            XCTAssertFalse(first.isNotifying)

            try await central.cancelPeripheralConnection(peripheral)

            XCTAssertFalse(mockPeripheral.isConnected)
        }
    }
}
