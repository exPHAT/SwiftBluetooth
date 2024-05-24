import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

final class LostConnectionPeripheralTests: CentralPeripheralTestCase {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testDiscoverServicesDuringDisconnect() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            XCTAssertTrue(mockPeripheral.isConnected)

            mockPeripheral.simulateDisconnection()

            do {
                let _ = try await peripheral.discoverServices()
                XCTFail("Failed to error when discovering services")
            } catch {
                let cbError = error as? CBError
                XCTAssertNotNil(cbError)
                XCTAssertEqual(cbError?.code, CBError.peripheralDisconnected)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadValueDuringDisconnect() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
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

            mockPeripheral.simulateDisconnection()

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
    func testWriteValueDuringDisconnect() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)
            let services = try await peripheral.discoverServices()

            var characteristics: [CBCharacteristic] = []

            for service in services {
                characteristics.append(contentsOf: try await peripheral.discoverCharacteristics(for: service))
            }

            let readableMockCharacteristic = mockCharacteristics.first(where: { $0.properties.contains(.read) && $0.properties.contains(.write) })!
            let characteristic = characteristics.first(where: { $0.uuid == readableMockCharacteristic.uuid })

            XCTAssertNotNil(characteristic)

            guard let characteristic = characteristic else { fatalError() }

            XCTAssertNil(characteristic.value)

            mockPeripheral.simulateDisconnection()

            do {
                let _ = try await peripheral.writeValue(Data([0x01]), for: characteristic, type: .withResponse)
                XCTFail("Failed to error when writing value")
            } catch {
                let cbError = error as? CBError
                XCTAssertNotNil(cbError)
                XCTAssertEqual(cbError?.code, CBError.peripheralDisconnected)
            }
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadStreamDuringDisconnect() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)
            let services = try await peripheral.discoverServices()

            var characteristics: [CBCharacteristic] = []

            for service in services {
                characteristics.append(contentsOf: try await peripheral.discoverCharacteristics(for: service))
            }

            let readableMockCharacteristic = mockCharacteristics.first(where: { $0.properties.contains(.read) && $0.properties.contains(.notify) })!
            let characteristic = characteristics.first(where: { $0.uuid == readableMockCharacteristic.uuid })

            XCTAssertNotNil(characteristic)

            guard let characteristic = characteristic else { fatalError() }

            XCTAssertNil(characteristic.value)

            mockPeripheral.simulateDisconnection()

            for await _ in peripheral.readValues(for: characteristic) {
                XCTAssert(false)
            }

            XCTAssertFalse(characteristic.isNotifying)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testSetNotifyDuringDisconnect() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            XCTAssertTrue(mockPeripheral.isConnected)

            let services = try await peripheral.discoverServices()

            XCTAssertGreaterThan(services.count, 0)

            let characteristics = try await peripheral.discoverCharacteristics(for: services[0])

            XCTAssertGreaterThan(characteristics.count, 0)

            let first = characteristics[0]

            mockPeripheral.simulateDisconnection()

            do {
                try await peripheral.setNotifyValue(true, for: first)
                XCTFail("Failed to error when setting notify")
            } catch {
                let cbError = error as? CBError
                XCTAssertNotNil(cbError)
                XCTAssertEqual(cbError?.code, CBError.peripheralDisconnected)
            }

            XCTAssertFalse(first.isNotifying)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testPeripheralSimultaniousDisconnectAndRead() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
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

            // TODO: Break this out into a separate AsyncSubscriptionQueue test?
            // Will also need to test that SwiftBluetooth.Peripheral implements a shared DispatchQueue (like this test is doing)
            var ran = 0
            let exp = XCTestExpectation()
            peripheral.readValue(for: characteristic) { result in
                exp.fulfill()
                XCTAssertEqual(0, ran)
                ran += 1
            }
            peripheral.responseMap.recieve(key: characteristic.uuid, withValue: .success(.init([0xFF])))
            peripheral.eventSubscriptions.recieve(.didDisconnect(nil))

            #if swift(>=5.8)
            await self.fulfillment(of: [exp])
            #else
            self.wait(for: [exp], timeout: 5)
            #endif
        }
    }
}
