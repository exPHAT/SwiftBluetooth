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

    override func setUp() {
        mockPeripheral.connectionDelegate?.reset()
        CBMCentralManagerMock.simulateAuthorization(.allowedAlways)
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        CBMCentralManagerMock.simulatePeripherals([mockPeripheral])
        mockPeripheral.simulateProximityChange(.near)
        central = CentralManager()
    }

    override func tearDown() async throws {
        var hadPeripheral = false

        if let peripheral {
            if mockPeripheral.isConnected {
                try await central.cancelPeripheralConnection(peripheral)
            }
            central.removePeripheral(peripheral.cbPeripheral)
            DispatchQueue.main.sync { }

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

            peripheral = nil

            if weakPeripheral != nil {
                XCTFail("Peripheral is being retained")
            }
        }

        peripheral = nil
        central = nil
        DispatchQueue.main.sync { }
        XCTAssertNil(weakCentral)

        CBMCentralManagerMock.tearDownSimulation()
    }
}
