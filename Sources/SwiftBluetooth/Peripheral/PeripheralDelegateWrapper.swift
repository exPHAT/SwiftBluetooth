import Foundation
import CoreBluetooth

class PeripheralDelegateWrapper: NSObject, CBPeripheralDelegate {
    private var parent: Peripheral

    init(parent: Peripheral) {
        self.parent = parent
    }

    var wrappedDelegate: PeripheralDelegate? {
        parent.delegate
    }

    // MARK: - CBPeripheralDelegate conformance

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        parent.eventSubscriptions.recieve(.discoveredServices(parent.services ?? []))
        wrappedDelegate?.peripheral(parent, didDiscoverServices: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        wrappedDelegate?.peripheral(parent, didDiscoverIncludedServicesFor: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Save known characteristics for later usage by UUID
        for characteristic in service.characteristics ?? [] {
            parent.knownCharacteristics[characteristic.uuid] = characteristic
        }

        parent.eventSubscriptions.recieve(.discoveredCharacteristics(service.characteristics ?? []))
        wrappedDelegate?.peripheral(parent, didDiscoverCharacteristicsFor: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        wrappedDelegate?.peripheral(parent, didDiscoverDescriptorsFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value {
            parent.responseMap.recieve(key: characteristic.uuid, withValue: value)
        }

        wrappedDelegate?.peripheral(parent, didUpdateValueFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        wrappedDelegate?.peripheral(parent, didUpdateValueFor: descriptor, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        parent.writeMap.recieve(key: characteristic.uuid, withValue: Void())
        wrappedDelegate?.peripheral(parent, didWriteValueFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        wrappedDelegate?.peripheral(parent, didWriteValueFor: descriptor, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        wrappedDelegate?.peripheral(parent, didUpdateNotificationStateFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        wrappedDelegate?.peripheral(parent, didReadRSSI: RSSI, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices services: [CBService]) {
        wrappedDelegate?.peripheral(parent, didModifyServices: services)
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        wrappedDelegate?.peripheralDidUpdateName(parent)
    }
}
