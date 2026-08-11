import XCTest
@testable @preconcurrency import CoreBluetoothMock
@testable import SwiftBluetoothMock

final class RegressionTests: CentralPeripheralTestCase {
    // State restoration can hand back a different CBPeripheral instance for a peripheral
    // we already track. Pointing at it without also becoming its delegate means no
    // callback ever arrives again, and every later operation hangs.
    func testUpdatingUnderlyingPeripheralReattachesDelegate() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            let peripheral = try await central.scanForPeripherals().first!
            let original = peripheral.cbPeripheral

            // A second manager produces its own instance for the same identifier,
            // which is what restoration does
            let otherCentral = CentralManager()
            try await otherCentral.wait(for: .poweredOn)
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
    func testDisconnectingAForgottenPeripheralLeavesItsDelegateAlone() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

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
    func testDiscoverDescriptorsForStaticCharacteristicCallsCompletionHandler() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
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

    func testDiscoverDescriptorsForUnknownCharacteristicReportsError() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
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
    func testConnectTimeoutNeverRacesWithSuccess() async throws {
        try await withTimeout(20) { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

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
    func testPoweringOffFinishesPendingWork() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
            XCTAssertTrue(central.isConnected(peripheral))

            let streamFinished = expectation(description: "value stream reported the disconnection")
            let stream = peripheral.readValues(for: characteristic)

            Task {
                do {
                    for try await _ in stream { }
                    XCTFail("Should report losing the peripheral rather than finishing quietly")
                } catch {
                    XCTAssertEqual((error as? CBError)?.code, .peripheralDisconnected)
                }

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
    func testReadRSSIFailsWhenPeripheralDisconnects() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
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
            peripheral.eventSubscriptions.receive(.didDisconnect(nil))

            await fulfillment(of: [failed], timeout: 5)
        }
    }

    func testDescriptorWriteFailsWhenPeripheralDisconnects() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
            let descriptors = try await peripheral.discoverDescriptors(for: characteristic)
            let descriptor = try XCTUnwrap(descriptors.first)

            let failed = expectation(description: "descriptor write failed")

            peripheral.writeValue(Data([0x01]), for: descriptor) { result in
                guard case .failure(let error) = result else {
                    XCTFail("Expected the write to fail once the peripheral disconnected")
                    return
                }

                XCTAssertEqual((error as? CBError)?.code, .peripheralDisconnected)
                failed.fulfill()
            }

            peripheral.eventSubscriptions.receive(.didDisconnect(nil))

            await fulfillment(of: [failed], timeout: 5)
        }
    }

    // Ending one stream used to decrement the notification count twice, turning
    // notifications off underneath any other stream on the same characteristic
    func testEndingOneValueStreamLeavesOthersRunning() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
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
                for try await _ in survivor {
                    survivorReceivedValue.fulfill()
                    break
                }
                survivorFinished.fulfill()
            }

            // Start a second stream and end it again
            var shortLived: AsyncThrowingStream<Data, Error>? = peripheral.readValues(for: characteristic)
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
    func testReadWithoutValueCompletesWithEmptyData() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
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

    // Scanning ends for several reasons and they don't mean the same thing: asking it to
    // stop is routine, losing the radio is a failure the caller needs to hear about
    func testScanFinishesQuietlyWhenStoppedAndThrowsWhenRadioIsLost() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)

            let stoppedScan = await central.scanForPeripherals()
            let stopped = expectation(description: "stopped scan finished without error")

            Task {
                do {
                    for try await _ in stoppedScan { }
                } catch {
                    XCTFail("Asking a scan to stop isn't a failure, got \(error)")
                }

                stopped.fulfill()
            }

            try await Task.sleep(nanoseconds: 100_000_000)
            central.stopScan()
            await fulfillment(of: [stopped], timeout: 5)

            let interruptedScan = await central.scanForPeripherals()
            let interrupted = expectation(description: "interrupted scan reported the failure")

            Task {
                do {
                    for try await _ in interruptedScan { }
                    XCTFail("Losing the radio should be reported rather than finishing quietly")
                } catch {
                    XCTAssertEqual((error as? CBError)?.code, .peripheralDisconnected)
                }

                interrupted.fulfill()
            }

            try await Task.sleep(nanoseconds: 100_000_000)
            CBMCentralManagerMock.simulatePowerOff()
            await fulfillment(of: [interrupted], timeout: 5)
        }
    }

    // The wrapper never forwarded this one, so a caller waiting to send more had no signal.
    // It's also what a deferred write-without-response waits for.
    func testPeripheralReadyToSendIsForwarded() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            let forwarded = expectation(description: "ready-to-send forwarded to the subscription")

            peripheral.eventSubscriptions.queue { event, done in
                guard case .isReadyToWriteWithoutResponse = event else { return }

                done()
                forwarded.fulfill()
            }

            let cbPeripheral = peripheral.cbPeripheral
            DispatchQueue.main.async {
                cbPeripheral.delegate?.peripheralIsReady(toSendWriteWithoutResponse: cbPeripheral)
            }

            await fulfillment(of: [forwarded], timeout: 5)
        }
    }

    // Every write without response has to be reported back, and none may be lost on the way.
    // CoreBluetoothMock refills its outgoing buffer too eagerly to exercise exhaustion here,
    // so this covers the reporting rather than the deferral.
    func testWritesWithoutResponseAreAllDelivered() async throws {
        try await withTimeout(20) { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))

            // Comfortably more than the mock's outgoing buffer, and issued without waiting
            // for each one, so the buffer runs out part way through
            let writes = 60
            let allWritten = expectation(description: "every write reported back")
            allWritten.expectedFulfillmentCount = writes

            for value in 0..<writes {
                peripheral.writeValue(Data([UInt8(value)]), for: characteristic, type: .withoutResponse) { _ in
                    allWritten.fulfill()
                }
            }

            await fulfillment(of: [allWritten], timeout: 10)

            let received = mockPeripheral.connectionDelegate as? ConnectablePeripheralDelegateSpec
            XCTAssertEqual(received?.writeCommandCount, writes, "Every write should have reached the peripheral")
        }
    }

    // Characteristic and descriptor writes shared one map keyed by UUID, so a descriptor
    // write could complete a characteristic write to the same UUID and vice versa
    func testDescriptorWritesDoNotCompleteCharacteristicWrites() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let uuid = try XCTUnwrap(peripheral.characteristic(for: .firstChar)).uuid

            let crossed = expectation(description: "descriptor write answered a characteristic write")
            crossed.isInverted = true

            let waiting = peripheral.writeMap.queue(key: uuid) { _, done in
                done()
                crossed.fulfill()
            }

            peripheral.descriptorWriteMap.receive(key: uuid, withValue: nil)
            await fulfillment(of: [crossed], timeout: 1)

            waiting.cancel()

            // The characteristic's own event still gets through
            let written = expectation(description: "characteristic write completed")

            peripheral.writeMap.queue(key: uuid) { _, done in
                done()
                written.fulfill()
            }

            peripheral.writeMap.receive(key: uuid, withValue: nil)
            await fulfillment(of: [written], timeout: 5)
        }
    }

    // Waiting was hardcoded to powered-on, so waiting for anything else was impossible
    // and a powered-off manager waited forever with no way out
    func testWaitingForAnyState() async throws {
        CBMCentralManagerMock.simulateInitialState(.poweredOff)
        central = CentralManager()

        try await withTimeout { [self] in
            // The state we're already in
            try await central.wait(for: .poweredOff)

            let poweredOn = Task { try await central.wait(for: .poweredOn) }
            try await Task.sleep(nanoseconds: 100_000_000)
            CBMCentralManagerMock.simulatePowerOn()
            _ = try await poweredOn.value

            // And back again, which the old API had no way to express
            let poweredOff = Task { try await central.wait(for: .poweredOff) }
            try await Task.sleep(nanoseconds: 100_000_000)
            CBMCentralManagerMock.simulatePowerOff()
            _ = try await poweredOff.value

            XCTAssertEqual(central.state, .poweredOff)
        }
    }

    func testWaitingForAStateThatNeverArrivesTimesOut() async throws {
        CBMCentralManagerMock.simulateInitialState(.poweredOff)
        central = CentralManager()

        try await withTimeout { [self] in
            do {
                try await central.wait(for: .poweredOn, timeout: 0.2)
                XCTFail("Should give up rather than waiting for a radio that never comes back")
            } catch {
                XCTAssertEqual(error as? CentralManagerError, .timedOut)
            }
        }
    }

    // The last of the crash-on-error signatures: it can report through the stream instead
    func testReadValuesForUnknownCharacteristicReportsError() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            do {
                // Never discovered, so it can't be mapped to a real characteristic
                for try await _ in peripheral.readValues(for: .unknownChar) {
                    XCTFail("Should not deliver values for an undiscovered characteristic")
                }

                XCTFail("Should report the undiscovered characteristic")
            } catch {
                XCTAssertEqual(error as? PeripheralError, .characteristicNotFound)
            }
        }
    }
}

extension Characteristic {
    static let unknownChar = Self("00000000-0000-0000-0009-000000000009")
}
