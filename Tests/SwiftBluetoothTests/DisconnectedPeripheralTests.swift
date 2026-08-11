import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

final class DisconnectedPeripheralTests: CentralPeripheralTestCase {
    func testScanOnOutOfRangePeripheral() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            try await central.wait(for: .poweredOn)

            mockPeripheral.simulateProximityChange(.outOfRange)

            let peripheral = try await central.scanForPeripherals(timeout: connectionTimeout).first
            XCTAssertNil(peripheral)
            XCTAssertFalse(central.isScanning)
        }
    }

    func testConnectTimeout() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

            mockPeripheral.simulateProximityChange(.outOfRange)

            do {
                try await central.connect(peripheral, timeout: connectionTimeout)

                XCTFail("Shouldn't connect to out of range peripherals")
            } catch {
                XCTAssertEqual((error as? CBError)?.code, .connectionTimeout)
            }
        }
    }

    func testConnectCancel() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

            mockPeripheral.simulateProximityChange(.outOfRange)

            let task = Task {
                try await central.connect(peripheral, timeout: .infinity)
            }

            task.cancel()

            do {
                let _ = try await task.value

                XCTFail("Should not connect successfully.")
            } catch {
                XCTAssertNotNil(error as? CancellationError)
            }
        }
    }

    func testReadValueOnDisconnectedPeripheral() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)
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

    func testSetNotifyOnDisconnectedPeripheral() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

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

    func testAccessDiscoveryDataAfterDisconnect() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            // Disconnect to test if the internal reference is dropped (it should not)
            try await central.cancelPeripheralConnection(peripheral)
            XCTAssertTrue(peripheral.state == .disconnected)

            // Request a new reference (should be the same as `peripheral`)
            let newPeripheralReference = try XCTUnwrap(central.retrievePeripherals(withIdentifiers: [peripheral.identifier]).first)
            XCTAssertNotNil(newPeripheralReference.discoveryInfo)
            XCTAssert(newPeripheralReference === peripheral) // Note: reference comparison
        }
    }
}
