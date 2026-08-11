import XCTest
@testable @preconcurrency import CoreBluetoothMock
@testable import SwiftBluetoothMock

final class RegressionTests: CentralPeripheralTestCase {
    // State restoration can hand back a different CBPeripheral instance for a peripheral
    // we already track. Pointing at it without also becoming its delegate means no
    // callback ever arrives again, and every later operation hangs.
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testUpdatingUnderlyingPeripheralReattachesDelegate() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            let peripheral = await central.scanForPeripherals().first!
            let original = peripheral.cbPeripheral

            // A second manager produces its own instance for the same identifier,
            // which is what restoration does
            let otherCentral = CentralManager()
            try await otherCentral.waitUntilReady()
            let restored = try XCTUnwrap(otherCentral.retrievePeripherals(withIdentifiers: [peripheral.identifier]).first).cbPeripheral

            XCTAssertFalse(restored === original, "Expected the other manager to make its own instance")

            let delegateBeforeUpdate = restored.delegate
            XCTAssertNotNil(delegateBeforeUpdate)

            XCTAssertTrue(central.peripheral(restored) === peripheral, "Should recycle the peripheral we already have")
            XCTAssertTrue(peripheral.cbPeripheral === restored, "Should point at the new instance")
            XCTAssertNotNil(restored.delegate)
            XCTAssertFalse(restored.delegate === delegateBeforeUpdate, "Should have taken over as delegate")
        }
    }

    // A disconnection arriving for a peripheral we've been asked to forget used to build a
    // second wrapper for it, which took over delegate callbacks from the one still held
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testDisconnectingAForgottenPeripheralLeavesItsDelegateAlone() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!

            let cbPeripheral = peripheral.cbPeripheral
            let delegate = try XCTUnwrap(cbPeripheral.delegate)

            XCTAssertTrue(central.forgetPeripheral(peripheral))

            // Whatever the peripheral was up to still finishes reporting back to us
            let managerDelegate = try XCTUnwrap(central.centralManager.delegate)
            managerDelegate.centralManager(central.centralManager, didDisconnectPeripheral: cbPeripheral, error: nil)

            XCTAssertTrue(cbPeripheral.delegate === delegate, "Should not have replaced the delegate of a peripheral we forgot")
            XCTAssertNil(central.existingPeripheral(cbPeripheral), "Should not have started tracking it again")
        }
    }

    // This used to call the fire-and-forget overload, so the handler was never invoked
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testDiscoverDescriptorsForStaticCharacteristicCallsCompletionHandler() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let descriptors = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CBDescriptor], Error>) in
                peripheral.discoverDescriptors(for: .firstChar) { result in
                    cont.resume(with: result)
                }
            }

            XCTAssertFalse(descriptors.isEmpty)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testDiscoverDescriptorsForUnknownCharacteristicReportsError() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            // Never discovered, so it can't be mapped to a real characteristic
            do {
                _ = try await peripheral.discoverDescriptors(for: .unknownChar)
                XCTFail("Should not succeed for an undiscovered characteristic")
            } catch {
                XCTAssertEqual(error as? PeripheralError, .characteristicNotFound)
            }

            let failure = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Error?, Error>) in
                peripheral.readValue(for: .unknownChar) { result in
                    switch result {
                    case .success: cont.resume(returning: nil)
                    case .failure(let error): cont.resume(returning: error)
                    }
                }
            }

            XCTAssertEqual(failure as? PeripheralError, .characteristicNotFound)
        }
    }

    // The timeout and the connection event used to run on different queues, so both
    // could report a result for the same call
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testConnectTimeoutNeverRacesWithSuccess() async throws {
        try await withTimeout(20) { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!

            // Sweep across the mock's connection latency to land on the race
            for timeout in stride(from: 0.0, through: 0.05, by: 0.005) {
                let completions = expectation(description: "connect completed for timeout \(timeout)")
                completions.assertForOverFulfill = true

                central.connect(peripheral, timeout: timeout) { _ in
                    completions.fulfill()
                }

                await fulfillment(of: [completions], timeout: 5)

                // A connection can still land just after the timeout reported failure.
                // Settle it before the next attempt so each one starts disconnected.
                var attempts = 0
                while mockPeripheral.isConnected || central.isConnected(peripheral) {
                    if central.isConnected(peripheral) {
                        try await central.cancelPeripheralConnection(peripheral)
                    }

                    attempts += 1
                    guard attempts < 100 else { break }

                    try await Task.sleep(nanoseconds: 20_000_000)
                }

                XCTAssertFalse(central.isConnected(peripheral))
            }
        }
    }

    // Turning the radio off invalidates everything without CoreBluetooth reporting
    // a disconnection, so pending work has to be failed explicitly
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testPoweringOffFinishesPendingWork() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
            XCTAssertTrue(central.isConnected(peripheral))

            let streamFinished = expectation(description: "value stream finished")
            let stream = peripheral.readValues(for: characteristic)

            Task {
                for await _ in stream { }
                streamFinished.fulfill()
            }

            // Give the stream a moment to start before the radio goes away
            try await Task.sleep(nanoseconds: 100_000_000)
            CBMCentralManagerMock.simulatePowerOff()

            await fulfillment(of: [streamFinished], timeout: 5)
            XCTAssertTrue(central.connectedPeripherals.isEmpty)
        }
    }

    // These two had no disconnection handling at all, so losing the peripheral
    // mid-request left the caller waiting forever
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadRSSIFailsWhenPeripheralDisconnects() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            let failed = expectation(description: "readRSSI failed")

            peripheral.readRSSI { result in
                switch result {
                case .success:
                    XCTFail("Should not report a value after disconnecting")
                case .failure(let error):
                    XCTAssertEqual((error as? CBError)?.code, .peripheralDisconnected)
                }

                failed.fulfill()
            }

            // Delivered on the same queue as the request, so it always lands after registration
            peripheral.eventSubscriptions.recieve(.didDisconnect(nil))

            await fulfillment(of: [failed], timeout: 5)
        }
    }

    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testDescriptorWriteFailsWhenPeripheralDisconnects() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
            let descriptors = try await peripheral.discoverDescriptors(for: characteristic)
            let descriptor = try XCTUnwrap(descriptors.first)

            let failed = expectation(description: "descriptor write failed")

            peripheral.writeValue(Data([0x01]), for: descriptor) { error in
                XCTAssertEqual((error as? CBError)?.code, .peripheralDisconnected)
                failed.fulfill()
            }

            peripheral.eventSubscriptions.recieve(.didDisconnect(nil))

            await fulfillment(of: [failed], timeout: 5)
        }
    }

    // Ending one stream used to decrement the notification count twice, turning
    // notifications off underneath any other stream on the same characteristic
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testEndingOneValueStreamLeavesOthersRunning() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
            let mockCharacteristic = mockCharacteristics[0]

            let survivorReceivedValue = expectation(description: "surviving stream received a value")
            let survivorFinished = expectation(description: "surviving stream finished")
            let survivor = peripheral.readValues(for: characteristic)

            let survivorTask = Task {
                for await _ in survivor {
                    survivorReceivedValue.fulfill()
                    break
                }
                survivorFinished.fulfill()
            }

            // Start a second stream and end it again
            var shortLived: AsyncStream<Data>? = peripheral.readValues(for: characteristic)
            _ = shortLived
            shortLived = nil

            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertTrue(characteristic.isNotifying, "Notifications should stay on for the remaining stream")

            mockPeripheral.simulateValueUpdate(Data([0x01]), for: mockCharacteristic)

            await fulfillment(of: [survivorReceivedValue, survivorFinished], timeout: 5)
            _ = await survivorTask.result
        }
    }

    // A read that comes back without a value still has to be reported
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func testReadWithoutValueCompletesWithEmptyData() async throws {
        try await withTimeout { [self] in
            try await central.waitUntilReady()
            peripheral = await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
            XCTAssertNil(characteristic.value, "This test needs a characteristic that has never been read")

            let completed = expectation(description: "read completed")

            peripheral.responseMap.queue(key: characteristic.uuid) { result, done in
                switch result {
                case .success(let data):
                    XCTAssertEqual(data, Data())
                case .failure(let error):
                    XCTFail("Expected an empty value, got \(error)")
                }

                done()
                completed.fulfill()
            }

            // Delivered on the manager's queue, the same as a real value update would be
            let cbPeripheral = peripheral.cbPeripheral
            DispatchQueue.main.async {
                cbPeripheral.delegate?.peripheral(cbPeripheral, didUpdateValueFor: characteristic, error: nil)
            }

            await fulfillment(of: [completed], timeout: 5)
        }
    }
}

extension Characteristic {
    static let unknownChar = Self("00000000-0000-0000-0009-000000000009")
}
