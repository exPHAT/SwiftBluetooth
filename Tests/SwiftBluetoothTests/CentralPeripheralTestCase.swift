import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

fileprivate final class CentralManagerDelegateThreadChecker: CentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CentralManager) {
        XCTAssert(Thread.isMainThread)
    }

    func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral) {
        XCTAssert(Thread.isMainThread)
    }

    func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func centralManager(_ central: CentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: Peripheral) {
        XCTAssert(Thread.isMainThread)
    }

    func centralManager(_ central: CentralManager, didDiscover peripheral: Peripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        XCTAssert(Thread.isMainThread)
    }

    func centralManager(_ central: CentralManager, willRestoreState dict: [String: Any]) {
        XCTAssert(Thread.isMainThread)
    }

    func centralManager(_ central: CentralManager, didUpdateANCSAuthorizationFor peripheral: Peripheral) {
        XCTAssert(Thread.isMainThread)
    }
}

fileprivate final class PeripheralDelegateThreadChecker: PeripheralDelegate {
    func peripheral(_ peripheral: Peripheral, didDiscoverServices error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didModifyServices services: [CBService]) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheral(_ peripheral: Peripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        XCTAssert(Thread.isMainThread)
    }

    func peripheralDidUpdateName(_ peripheral: Peripheral) {
        XCTAssert(Thread.isMainThread)
    }
}

class CentralPeripheralTestCase: XCTestCase {
    let connectionTimeout: TimeInterval = 2

    private let centralDelegate = CentralManagerDelegateThreadChecker()
    private let peripheralDelegate = PeripheralDelegateThreadChecker()

    var central: CentralManager! {
        didSet {
            guard let central else { return }
            central.delegate = centralDelegate
        }
    }
    var peripheral: Peripheral! {
        didSet {
            guard let peripheral else { return }
            peripheral.delegate = peripheralDelegate
        }
    }

    /// The restore identifiers `simulateStateRestoration` has been asked about.
    private(set) var restorationRequests: [String] = []

    func noteRestorationRequest(_ key: String) {
        restorationRequests.append(key)
    }

    override func setUp() {
        restorationRequests = []
        mockPeripheral.connectionDelegate?.reset()
        CBMCentralManagerMock.simulateAuthorization(.allowedAlways)
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        CBMCentralManagerMock.simulatePeripherals([mockPeripheral])
        mockPeripheral.simulateProximityChange(.near)
        central = CentralManager()
    }

    /// Builds a manager CoreBluetoothMock hands `state` to during construction, the way iOS
    /// does when it relaunches an app to restore one.
    ///
    /// The state dictionary uses the `CBMCentralManagerRestoredState…` keys; peripherals must
    /// be `CBMPeripheralMock` instances from a previous manager, handed over directly — a
    /// fresh copy always starts `.disconnected`, so the connected/connecting instance itself
    /// is what carries the state across.
    func restoredCentral(identifier: String = "test-restore",
                         state: [String: Any],
                         delegate: CentralManagerDelegate? = nil) -> CentralManager {
        CBMCentralManagerMock.simulateStateRestoration = { [weak self] key in
            // Called synchronously from the manager's init, on the constructing thread
            self?.restorationRequests.append(key)
            return key == identifier ? state : nil
        }

        return CentralManager(delegate: delegate, restoreIdentifier: identifier)
    }

    /// Runs out anything still in flight across the queues callbacks travel through.
    ///
    /// Draining a queue can put more work back onto it: a delegate callback lands on the
    /// manager's queue, which hands the event to its subscribers on the event queue, which
    /// can then deliver to the peripheral's. Each pass moves the work along one step, so
    /// they have to be drained together and more than once.
    private func settleQueues(rounds: Int = 3) {
        for _ in 0..<rounds {
            DispatchQueue.main.sync { }
            central?.eventQueue.sync { }
            peripheral?.eventQueue.sync { }
        }
    }

    override func tearDown() async throws {
        var hadPeripheral = false

        if let peripheral {
            if mockPeripheral.isConnected {
                try await central.cancelPeripheralConnection(peripheral)
            }

            // Let any callback still in flight land before dropping the peripheral,
            // since delivering one registers it with the central again
            settleQueues()

            central.removePeripheral(peripheral.cbPeripheral)
            settleQueues()

            hadPeripheral = true

            XCTAssertTrue(peripheral.responseMap.isEmpty)
            XCTAssertTrue(peripheral.writeMap.isEmpty)
            XCTAssertTrue(peripheral.descriptorWriteMap.isEmpty)
            XCTAssertTrue(peripheral.descriptorMap.isEmpty)
            XCTAssertTrue(peripheral.eventSubscriptions.isEmpty)
        }

        XCTAssertTrue(central.eventSubscriptions.isEmpty)

        let centralRef = WeakRef(central)

        if hadPeripheral {
            let peripheralRef = WeakRef(peripheral)

            peripheral = nil

            XCTAssertTrue(peripheralRef.isReleased, "Peripheral is being retained")
        }

        peripheral = nil
        central = nil
        DispatchQueue.main.sync { }
        XCTAssertTrue(centralRef.isReleased, "CentralManager is being retained")

        // A global — leaking it across tests would restore state into unrelated managers
        CBMCentralManagerMock.simulateStateRestoration = nil
        CBMCentralManagerMock.tearDownSimulation()
    }
}

/// Watches an object without keeping it alive, so a test can tell whether it was released.
private final class WeakRef<Object: AnyObject> {
    private weak var object: Object?

    init(_ object: Object) {
        self.object = object
    }

    var isReleased: Bool {
        object == nil
    }
}
