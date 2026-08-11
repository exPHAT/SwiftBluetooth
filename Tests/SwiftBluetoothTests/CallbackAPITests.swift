import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

/// The completion-handler API is a first-class alternative to the async one, so it gets
/// the same walk through connect, discover, read, write and subscribe.
final class CallbackAPITests: CentralPeripheralTestCase {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testWaitUntilReady() async throws {
        CBMCentralManagerMock.simulateInitialState(.poweredOff)
        central = CentralManager()

        let ready = expectation(description: "central ready")

        central.waitUntilReady { result in
            if case .failure(let error) = result {
                XCTFail("Should become ready, got \(error)")
            }

            ready.fulfill()
        }

        CBMCentralManagerMock.simulatePowerOn()

        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(central.state, .poweredOn)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testScanConnectDiscoverReadWrite() async throws {
        try await central.waitUntilReady()

        let found = expectation(description: "peripheral found")
        found.assertForOverFulfill = false

        let scan = central.scanForPeripherals { [self] discovered in
            guard peripheral == nil else { return }

            peripheral = discovered
            found.fulfill()
        }

        await fulfillment(of: [found], timeout: 5)
        scan.cancel()
        XCTAssertFalse(central.isScanning)

        let connected = expectation(description: "connected")
        central.connect(peripheral, timeout: connectionTimeout) { result in
            if case .failure(let error) = result {
                XCTFail("Should connect, got \(error)")
            }

            connected.fulfill()
        }
        await fulfillment(of: [connected], timeout: 5)

        let discoveredServices = expectation(description: "services discovered")
        var services: [CBService] = []

        peripheral.discoverServices { result in
            services = (try? result.get()) ?? []
            discoveredServices.fulfill()
        }
        await fulfillment(of: [discoveredServices], timeout: 5)
        XCTAssertEqual(services.count, mockServices.count)

        let discoveredCharacteristics = expectation(description: "characteristics discovered")
        discoveredCharacteristics.expectedFulfillmentCount = services.count

        for service in services {
            peripheral.discoverCharacteristics(for: service) { result in
                if case .failure(let error) = result {
                    XCTFail("Should discover characteristics, got \(error)")
                }

                discoveredCharacteristics.fulfill()
            }
        }
        await fulfillment(of: [discoveredCharacteristics], timeout: 5)

        let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))

        let written = expectation(description: "value written")
        peripheral.writeValue(Data([0x01]), for: characteristic, type: .withResponse) { error in
            XCTAssertNil(error)
            written.fulfill()
        }
        await fulfillment(of: [written], timeout: 5)

        let read = expectation(description: "value read")
        peripheral.readValue(for: characteristic) { result in
            XCTAssertEqual(try? result.get(), Data([0x01]))
            read.fulfill()
        }
        await fulfillment(of: [read], timeout: 5)

        let readRSSI = expectation(description: "rssi read")
        peripheral.readRSSI { result in
            XCTAssertNotNil(try? result.get())
            readRSSI.fulfill()
        }
        await fulfillment(of: [readRSSI], timeout: 5)

        let disconnected = expectation(description: "disconnected")
        central.cancelPeripheralConnection(peripheral) { result in
            if case .failure(let error) = result {
                XCTFail("Should disconnect, got \(error)")
            }

            disconnected.fulfill()
        }
        await fulfillment(of: [disconnected], timeout: 5)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadValuesDeliversUpdatesUntilCancelled() async throws {
        try await central.waitUntilReady()
        peripheral = await central.scanForPeripherals().first!
        try await central.connect(peripheral, timeout: connectionTimeout)

        for service in try await peripheral.discoverServices() {
            _ = try await peripheral.discoverCharacteristics(for: service)
        }

        let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
        let received = expectation(description: "received updates")
        received.expectedFulfillmentCount = 3

        let subscription = peripheral.readValues(for: characteristic) { _ in
            received.fulfill()
        }

        // CoreBluetoothMock takes a moment to actually start notifying
        try await peripheral.setNotifyValue(true, for: characteristic)

        for value in 0..<3 {
            mockPeripheral.simulateValueUpdate(Data([UInt8(value)]), for: mockCharacteristics[0])
        }

        await fulfillment(of: [received], timeout: 5)

        subscription.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Notifications were also asked for directly, so they outlive the subscription
        XCTAssertTrue(characteristic.isNotifying)

        try await peripheral.setNotifyValue(false, for: characteristic)
        XCTAssertFalse(characteristic.isNotifying)
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testSetNotifyValueReportsState() async throws {
        try await central.waitUntilReady()
        peripheral = await central.scanForPeripherals().first!
        try await central.connect(peripheral, timeout: connectionTimeout)

        for service in try await peripheral.discoverServices() {
            _ = try await peripheral.discoverCharacteristics(for: service)
        }

        let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))

        let notifying = expectation(description: "notifications enabled")
        peripheral.setNotifyValue(true, for: characteristic) { result in
            XCTAssertEqual(try? result.get(), true)
            notifying.fulfill()
        }
        await fulfillment(of: [notifying], timeout: 5)
        XCTAssertTrue(characteristic.isNotifying)

        let stopped = expectation(description: "notifications disabled")
        peripheral.setNotifyValue(false, for: characteristic) { result in
            XCTAssertEqual(try? result.get(), false)
            stopped.fulfill()
        }
        await fulfillment(of: [stopped], timeout: 5)
        XCTAssertFalse(characteristic.isNotifying)
    }
}
