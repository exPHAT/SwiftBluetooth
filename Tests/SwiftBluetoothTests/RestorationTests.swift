import XCTest
@testable @preconcurrency import CoreBluetoothMock
@testable import SwiftBluetoothMock

/// Records restoration-related callbacks and the order they arrive in.
private final class RestorationSpy: CentralManagerDelegate {
    private let lock = NSLock()
    private var _events: [String] = []
    private var _typedStates: [CentralManagerRestoredState] = []
    private var _rawDicts: [[String: Any]] = []
    private var _connects: [UUID] = []
    private var _restoredStateVisibleAtFirstStateUpdate: Bool?

    var events: [String] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    var typedStates: [CentralManagerRestoredState] {
        lock.lock(); defer { lock.unlock() }
        return _typedStates
    }

    var rawDicts: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return _rawDicts
    }

    var connects: [UUID] {
        lock.lock(); defer { lock.unlock() }
        return _connects
    }

    /// Whether `restoredState` was already readable when the first state update arrived.
    var restoredStateVisibleAtFirstStateUpdate: Bool? {
        lock.lock(); defer { lock.unlock() }
        return _restoredStateVisibleAtFirstStateUpdate
    }

    func centralManager(_ central: CentralManager, willRestore state: CentralManagerRestoredState) {
        lock.lock(); defer { lock.unlock() }
        _events.append("willRestore")
        _typedStates.append(state)
    }

    func centralManager(_ central: CentralManager, willRestoreState dict: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        _events.append("willRestoreState")
        _rawDicts.append(dict)
    }

    func centralManagerDidUpdateState(_ central: CentralManager) {
        let restoredVisible = central.restoredState != nil

        lock.lock(); defer { lock.unlock() }
        _events.append("didUpdateState")
        if _restoredStateVisibleAtFirstStateUpdate == nil {
            _restoredStateVisibleAtFirstStateUpdate = restoredVisible
        }
    }

    func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral) {
        lock.lock(); defer { lock.unlock() }
        _events.append("didConnect")
        _connects.append(peripheral.identifier)
    }
}

/// A lock-guarded slot for observing a completion from another thread.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value?

    var value: Value? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _value = newValue
        }
    }
}

final class RestorationTests: CentralPeripheralTestCase {
    // MARK: - Delivery

    func testRestoredPeripheralsAreDeliveredToTheDelegate() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            let restored = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                           delegate: spy)

            XCTAssertEqual(spy.typedStates.count, 1, "The typed callback fires exactly once")
            XCTAssertEqual(spy.typedStates.first?.peripherals.map(\.identifier), [peripheral.identifier])
            XCTAssertEqual(spy.rawDicts.count, 1, "The raw-dict callback also fires")
            XCTAssertNotNil(spy.rawDicts.first?[CBMCentralManagerRestoredStatePeripheralsKey])
            XCTAssertNotNil(restored.restoredState)
        }
    }

    func testRestorationHappensBeforeTheFirstStateUpdate() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            let restored = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                           delegate: spy)
            try await restored.wait(for: .poweredOn)

            XCTAssertEqual(Array(spy.events.prefix(2)), ["willRestore", "willRestoreState"],
                           "Restoration precedes everything, typed before raw")
            XCTAssertTrue(spy.events.contains("didUpdateState"))
            XCTAssertEqual(spy.restoredStateVisibleAtFirstStateUpdate, true,
                           "restoredState is final by the first state update")
        }
    }

    func testRestoredPeripheralIsTheObjectTheManagerHandsOut() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            let restored = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                           delegate: spy)

            // Before the first state update, when retrievePeripherals still returns nothing
            let viaLookup = try XCTUnwrap(restored.peripheral(withIdentifier: peripheral.identifier),
                                          "The registry lookup works before .poweredOn")
            XCTAssertTrue(viaLookup === spy.typedStates.first?.peripherals.first)

            try await restored.wait(for: .poweredOn)
            let viaRetrieve = try XCTUnwrap(restored.retrievePeripherals(withIdentifiers: [peripheral.identifier]).first)
            XCTAssertTrue(viaRetrieve === viaLookup, "Retrieval hands back the same wrapper")
        }
    }

    func testRestorationIsNotDeliveredToADelegateAttachedAfterConstruction() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            let handed = peripheral.cbPeripheral

            let restored = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                           delegate: nil)
            let spy = RestorationSpy()
            restored.delegate = spy
            try await restored.wait(for: .poweredOn)

            XCTAssertFalse(spy.events.contains("willRestore"))
            XCTAssertFalse(spy.events.contains("willRestoreState"))
            XCTAssertEqual(restored.restoredState?.peripherals.map(\.identifier), [peripheral.identifier],
                           "A late delegate reads restoredState instead")
        }
    }

    // MARK: - Connection bookkeeping

    func testRestoredConnectedPeripheralIsMarkedConnected() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)
            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            let restored = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                           delegate: spy)

            let adopted = try XCTUnwrap(spy.typedStates.first?.peripherals.first)
            XCTAssertEqual(adopted.state, .connected)
            XCTAssertTrue(restored.isConnected(adopted))
            XCTAssertTrue(restored.connectedPeripherals.contains(adopted))
            XCTAssertTrue(spy.connects.isEmpty, "Restoration is not a connection event")
        }
    }

    func testRestoredPendingConnectIsNotMarkedConnected() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

            mockPeripheral.simulateProximityChange(.outOfRange)
            XCTAssertTrue(central.connectPersistently(peripheral))
            XCTAssertEqual(peripheral.state, .connecting)

            // Re-arming a request that's still pending is allowed — a radio
            // power-cycle can leave a stale .connecting behind, and re-arming
            // is exactly what connectPersistently exists for
            XCTAssertTrue(central.connectPersistently(peripheral))
            XCTAssertEqual(peripheral.state, .connecting)

            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            let restored = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                           delegate: spy)

            let adopted = try XCTUnwrap(spy.typedStates.first?.peripherals.first)
            XCTAssertEqual(adopted.state, .connecting, "A restored pending connect is still pending")
            XCTAssertFalse(restored.isConnected(adopted))
            XCTAssertTrue(restored.connectedPeripherals.isEmpty)

            // Settle the pending request so the next test starts clean; the synchronous
            // closure picks the fire-and-forget overload over the async one
            let settlePending: () -> Void = { self.central.cancelPeripheralConnection(self.peripheral) }
            settlePending()
            mockPeripheral.simulateProximityChange(.near)
        }
    }

    func testCancellingAConnectionOnARestoredPeripheralWaitsForTheDisconnection() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)
            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            let restored = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                           delegate: spy)
            try await restored.wait(for: .poweredOn)
            let adopted = try XCTUnwrap(spy.typedStates.first?.peripherals.first)

            let outcome = Box<Result<Void, Error>>()
            let completed = expectation(description: "cancel completed")

            restored.cancelPeripheralConnection(adopted) { result in
                outcome.value = result
                completed.fulfill()
            }

            // This used to report success immediately without ever asking CoreBluetooth,
            // because a restored connection was never in the manager's connected set
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertNil(outcome.value, "Should wait for the disconnection, not report success straight away")

            // The mock can't disconnect an instance another manager owns, so deliver the
            // outcome the way CoreBluetooth would
            let managerDelegate = try XCTUnwrap(restored.centralManager.delegate)
            DispatchQueue.main.async {
                managerDelegate.centralManager(restored.centralManager, didDisconnectPeripheral: handed, error: nil)
            }

            await fulfillment(of: [completed], timeout: 5)
            guard case .success = try XCTUnwrap(outcome.value) else {
                return XCTFail("Expected the delivered disconnection to complete the cancel")
            }
            XCTAssertFalse(restored.isConnected(adopted))
        }
    }

    func testCancelledAsyncConnectTearsDownThePendingRequest() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

            mockPeripheral.simulateProximityChange(.outOfRange)

            let pending = Task { [self] in
                try await self.central.connect(self.peripheral)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            pending.cancel()

            guard case .failure = await pending.result else {
                return XCTFail("Cancelling the task should throw rather than connect")
            }

            // Let the torn-down request's disconnection settle before watching for connects
            try await Task.sleep(nanoseconds: 300_000_000)

            let connected = expectation(description: "connected after the request was torn down")
            connected.isInverted = true
            let watcher = central.eventSubscriptions.queue { event, _ in
                if case .connected = event { connected.fulfill() }
            }

            mockPeripheral.simulateProximityChange(.near)
            await fulfillment(of: [connected], timeout: 1)
            watcher.cancel()

            XCTAssertEqual(peripheral.state, .disconnected)
        }
    }

    func testCancellingAPendingConnectTearsDownTheRequest() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

            mockPeripheral.simulateProximityChange(.outOfRange)
            XCTAssertTrue(central.connectPersistently(peripheral))
            XCTAssertEqual(peripheral.state, .connecting)

            // Neither side reports connected, so this takes the guard's else
            // branch: the cancel still reaches CoreBluetooth
            XCTAssertFalse(central.isConnected(peripheral))
            try await central.cancelPeripheralConnection(peripheral)

            try await Task.sleep(nanoseconds: 300_000_000)

            let connected = expectation(description: "connected after the request was torn down")
            connected.isInverted = true
            let watcher = central.eventSubscriptions.queue { event, _ in
                if case .connected = event { connected.fulfill() }
            }

            mockPeripheral.simulateProximityChange(.near)
            await fulfillment(of: [connected], timeout: 1)
            watcher.cancel()

            XCTAssertEqual(peripheral.state, .disconnected)
        }
    }

    func testCancellingAPendingConnectFailsItsInFlightCompletion() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!

            mockPeripheral.simulateProximityChange(.outOfRange)

            // An infinite-timeout connect waiting on the request the cancel is
            // about to destroy — its completion must still fire, because
            // CoreBluetooth reports nothing for a torn-down pending request
            let completed = expectation(description: "in-flight connect completed")
            central.connect(peripheral) { result in
                guard case .failure = result else {
                    return XCTFail("A torn-down request should fail, not connect")
                }
                completed.fulfill()
            }

            try await Task.sleep(nanoseconds: 300_000_000)
            try await central.cancelPeripheralConnection(peripheral)

            await fulfillment(of: [completed], timeout: 5)
            mockPeripheral.simulateProximityChange(.near)
        }
    }

    func testConnectPersistentlyIgnoresAnAlreadyConnectedPeripheral() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            let duplicate = expectation(description: "second didConnect for a connected peripheral")
            duplicate.isInverted = true
            let watcher = central.eventSubscriptions.queue { event, _ in
                if case .connected = event { duplicate.fulfill() }
            }

            XCTAssertFalse(central.connectPersistently(peripheral),
                           "Nothing was asked for, so there is nothing to wait for")
            await fulfillment(of: [duplicate], timeout: 0.5)
            watcher.cancel()

            // A disconnected peripheral is asked for, and the request does its job
            try await central.cancelPeripheralConnection(peripheral)

            let reconnected = expectation(description: "reconnected")
            let reconnectWatcher = central.eventSubscriptions.queue { event, done in
                if case .connected = event {
                    reconnected.fulfill()
                    done()
                }
            }

            XCTAssertTrue(central.connectPersistently(peripheral))
            await fulfillment(of: [reconnected], timeout: 5)
            _ = reconnectWatcher
        }
    }

    // MARK: - Peripheral seeding

    func testRestoredPeripheralSeedsDiscoveredCharacteristics() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            _ = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                delegate: spy)

            let adopted = try XCTUnwrap(spy.typedStates.first?.peripherals.first)
            XCTAssertNotNil(adopted.characteristic(for: .firstChar),
                            "Characteristics discovered by the previous launch resolve without re-discovery")
        }
    }

    func testRestoredPeripheralKeepsNotificationsThePreviousLaunchTurnedOn() async throws {
        try await withTimeout { [self] in
            try await central.wait(for: .poweredOn)
            peripheral = try await central.scanForPeripherals().first!
            try await central.connect(peripheral, timeout: connectionTimeout)

            for service in try await peripheral.discoverServices() {
                _ = try await peripheral.discoverCharacteristics(for: service)
            }

            let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))
            try await peripheral.setNotifyValue(true, for: characteristic)
            XCTAssertTrue(characteristic.isNotifying)

            let handed = peripheral.cbPeripheral

            let spy = RestorationSpy()
            _ = restoredCentral(state: [CBMCentralManagerRestoredStatePeripheralsKey: [handed]],
                                delegate: spy)

            let adopted = try XCTUnwrap(spy.typedStates.first?.peripherals.first)
            XCTAssertTrue(adopted.notifyingState.isExternallyNotifying(forKey: characteristic.uuid),
                          "An already-on notification is adopted as an external subscription")
        }
    }

    // MARK: - Restored scans

    func testRestoredScanIsReported() async throws {
        try await withTimeout { [self] in
            let services = [CBMUUID(string: "00000000-0000-0000-0001-000000000000")]
            let options: [String: Any] = [CBMCentralManagerScanOptionAllowDuplicatesKey: true]

            let spy = RestorationSpy()
            _ = restoredCentral(state: [CBMCentralManagerRestoredStateScanServicesKey: services,
                                        CBMCentralManagerRestoredStateScanOptionsKey: options],
                                delegate: spy)

            let state = try XCTUnwrap(spy.typedStates.first)
            XCTAssertEqual(state.scanServices, services)
            XCTAssertNotNil(state.scanOptions)
            XCTAssertTrue(state.wasScanning)
            XCTAssertTrue(state.peripherals.isEmpty)
            XCTAssertNotNil(state.dictionary[CBMCentralManagerRestoredStateScanServicesKey],
                            "The untranslated dictionary still carries everything")
        }
    }

    // MARK: - Restore identifier plumbing

    func testRestoreIdentifierIsForwardedToCoreBluetooth() async throws {
        let restored = restoredCentral(identifier: "forwarding-check", state: [:])

        XCTAssertEqual(restorationRequests, ["forwarding-check"],
                       "The identifier reached CoreBluetooth's restoration lookup")
        XCTAssertEqual(restored.restoreIdentifier, "forwarding-check")
    }

    func testManagerWithoutMatchingRestorationIsNotRestored() async throws {
        let spy = RestorationSpy()
        CBMCentralManagerMock.simulateStateRestoration = { key in
            key == "someone-else" ? [CBMCentralManagerRestoredStateScanServicesKey: [CBMUUID]()] : nil
        }

        let restored = CentralManager(delegate: spy, restoreIdentifier: "test-restore")

        XCTAssertNil(restored.restoredState)
        XCTAssertFalse(spy.events.contains("willRestore"))
        XCTAssertFalse(spy.events.contains("willRestoreState"))
    }

    func testRestoreIdentifierOverridesTheSameKeyInOptions() async throws {
        CBMCentralManagerMock.simulateStateRestoration = { [weak self] key in
            self?.noteRestorationRequest(key)
            return nil
        }

        let restored = CentralManager(restoreIdentifier: "winner",
                                      options: [CBMCentralManagerOptionRestoreIdentifierKey: "loser"])

        XCTAssertEqual(restored.restoreIdentifier, "winner")
        XCTAssertEqual(restorationRequests, ["winner"])
    }
}
