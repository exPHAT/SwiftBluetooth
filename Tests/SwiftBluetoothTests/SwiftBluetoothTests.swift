import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

final class SwiftBluetoothTests: XCTestCase {
    var exp: XCTestExpectation!

    var central: CentralManager!
    var peripheral: Peripheral!

    override func setUp() {
        mockPeripheral.connectionDelegate?.reset()
        CBMCentralManagerMock.simulatePeripherals([mockPeripheral])
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        central = CentralManager()
    }

    override func tearDown() {
        if let peripheral {
            XCTAssertTrue(peripheral.responseMap.isEmpty)
            XCTAssertTrue(peripheral.writeMap.isEmpty)
            XCTAssertTrue(peripheral.descriptorMap.isEmpty)
            XCTAssertTrue(peripheral.eventSubscriptions.isEmpty)
        }

        XCTAssertTrue(central.eventSubscriptions.isEmpty)

        central = nil
        peripheral = nil
        CBMCentralManagerMock.tearDownSimulation()
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testAwaitReadyCold() async throws {
        CBMCentralManagerMock.simulateInitialState(.poweredOff)

        try await withTimeout { [self] in
            central = CentralManager()

            XCTAssertNotEqual(central.state, .poweredOn)

            CBMCentralManagerMock.simulatePowerOn()
            await central.waitUntilReady()

            XCTAssertEqual(central.state, .poweredOn)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testAwaitReadyWarm() async throws {
        CBMCentralManagerMock.simulateInitialState(.poweredOn)

        try await withTimeout { [self] in
            central = CentralManager()
            await central.waitUntilReady()

            XCTAssertEqual(central.state, .poweredOn)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testFindConnectDiscover() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            await central.waitUntilReady()

            peripheral = await central.scanForPeripherals().first

            XCTAssertNotNil(peripheral)
            guard let peripheral else { fatalError() }

            XCTAssertFalse(mockPeripheral.isConnected)

            try await central.connect(peripheral)

            XCTAssertTrue(mockPeripheral.isConnected)

            let services = try await peripheral.discoverServices()

            XCTAssertEqual(services.count, mockPeripheral.services?.count)

            for service in services {
                let foundService = mockServices.find(mockOf: service)

                XCTAssertNotNil(foundService)

                guard let foundService = foundService else { fatalError() }

                let characteristics = try await peripheral.discoverCharacteristics(for: service)

                XCTAssertEqual(characteristics.count, foundService.characteristics?.count)
            }

            try await central.cancelPeripheralConnection(peripheral)

            XCTAssertFalse(mockPeripheral.isConnected)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadValue() async throws {
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

            let value = try await peripheral.readValue(for: characteristic)

            XCTAssertGreaterThan(value.count, 0)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadWriteValue() async throws {
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

            let mutableMockCharacteristic = mockCharacteristics.first(where: { $0.properties.contains(.read) && $0.properties.contains(.write) })!
            let characteristic = characteristics.first(where: { $0.uuid == mutableMockCharacteristic.uuid })

            XCTAssertNotNil(characteristic)

            guard let characteristic = characteristic else { fatalError() }

            XCTAssertNil(characteristic.value)

            var value = try await peripheral.readValue(for: characteristic)

            XCTAssertEqual(value, characteristic.value)
            XCTAssertEqual(value, Data([0x00]))

            try await peripheral.writeValue(.init([0x01]), for: characteristic, type: .withResponse)

            XCTAssertEqual(value, characteristic.value)
            XCTAssertEqual(value, Data([0x00]))

            value = try await peripheral.readValue(for: characteristic)

            XCTAssertEqual(value, characteristic.value)
            XCTAssertEqual(value, Data([0x01]))
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testSubscribeToCharacteristic() async throws {
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

            let mutableMockCharacteristic = mockCharacteristics.first(where: { $0.properties.contains(.read) &&
                                                                               $0.properties.contains(.notify) &&
                                                                               $0.properties.contains(.write) })!
            let characteristic = characteristics.first(where: { $0.uuid == mutableMockCharacteristic.uuid })

            XCTAssertNotNil(characteristic)

            guard let characteristic = characteristic else { fatalError() }

            XCTAssertNil(characteristic.value)
            XCTAssertFalse(characteristic.isNotifying)

            var stream: AsyncStream<Data>? = peripheral.readValues(for: characteristic)

            // CoreBluetoothMock adds some delays to its ability to simulate
            // Using our async setNotifyValue we can wait for notifying to actually be true
            try await peripheral.setNotifyValue(true, for: characteristic)
            XCTAssertTrue(characteristic.isNotifying)

            mockPeripheral.simulateValueUpdate(.init([0x10]), for: mutableMockCharacteristic)
            mockPeripheral.simulateValueUpdate(.init([0x11]), for: mutableMockCharacteristic)
            mockPeripheral.simulateValueUpdate(.init([0x12]), for: mutableMockCharacteristic)

            var count = 0
            for await value in stream! {
                switch (count, value[0]) {
                case (0, 0x10), (1, 0x11), (2, 0x12): break
                default: XCTAssert(false)
                }

                count += 1

                if count >= 3 {
                    break
                }
            }

            // Still true because the stream hasn't actually been deallocated
            XCTAssertTrue(characteristic.isNotifying)

            try await peripheral.setNotifyValue(false, for: characteristic)
            XCTAssertFalse(characteristic.isNotifying)

            // Set stream to nil to deallocate AsyncStream
            stream = nil

            try await peripheral.setNotifyValue(false, for: characteristic)
            XCTAssertFalse(characteristic.isNotifying)

            try await peripheral.setNotifyValue(false, for: characteristic)
            XCTAssertFalse(characteristic.isNotifying)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testSubscribeBreakLoop() async throws {
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

            let mutableMockCharacteristic = mockCharacteristics.first(where: { $0.properties.contains(.read) &&
                                                                               $0.properties.contains(.notify) &&
                                                                               $0.properties.contains(.write) })!
            let characteristic = characteristics.first(where: { $0.uuid == mutableMockCharacteristic.uuid })

            XCTAssertNotNil(characteristic)

            guard let characteristic = characteristic else { fatalError() }

            XCTAssertNil(characteristic.value)
            XCTAssertFalse(characteristic.isNotifying)

            // CoreBluetoothMock adds some delays to its ability to simulate
            // Using our async setNotifyValue we can wait for notifying to actually be true
            try await peripheral.setNotifyValue(true, for: characteristic)
            XCTAssertTrue(characteristic.isNotifying)

            let exp = self.expectation(description: "Should break out of the loop")

            Task {
                for await _ in peripheral.readValues(for: characteristic) {
                    // Do nothing in this loop and never cause it to break
                }

                exp.fulfill()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
                mockPeripheral.simulateValueUpdate(.init([0x10]), for: mutableMockCharacteristic)
                mockPeripheral.simulateValueUpdate(.init([0x11]), for: mutableMockCharacteristic)
                mockPeripheral.simulateValueUpdate(.init([0x12]), for: mutableMockCharacteristic)

                peripheral.setNotifyValue(false, for: characteristic)
            }

            #if swift(>=5.8)
            await self.fulfillment(of: [exp])
            #else
            self.wait(for: [exp], timeout: 5)
            #endif
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testPeripheralDisconnect() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral)

            XCTAssertTrue(mockPeripheral.isConnected)

            try await central.cancelPeripheralConnection(peripheral)

            XCTAssertFalse(mockPeripheral.isConnected)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testPeripheralRSSI() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral)

            let rssi = try await peripheral.readRSSI()

            XCTAssertNotNil(rssi)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testPeripheralNotConnectedCancel() async throws {
        try await withTimeout { [self] in
            central = CentralManager()
            await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!

            try? await central.cancelPeripheralConnection(peripheral)

            let connectResult = try? await central.connect(peripheral)

            XCTAssertNotNil(connectResult)
            XCTAssertTrue(mockPeripheral.isConnected)
        }
    }
}
