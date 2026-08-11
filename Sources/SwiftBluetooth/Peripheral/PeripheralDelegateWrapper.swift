import Foundation
import CoreBluetooth

internal final class PeripheralDelegateWrapper: NSObject, CBPeripheralDelegate {
    private weak var parent: Peripheral?

    init(parent: Peripheral) {
        self.parent = parent
    }

    // MARK: - CBPeripheralDelegate conformance

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let parent = parent else { return }
        parent.eventSubscriptions.receive(.discoveredServices(parent.services ?? [], error))
        parent.delegate?.peripheral(parent, didDiscoverServices: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        guard let parent = parent else { return }
        parent.delegate?.peripheral(parent, didDiscoverIncludedServicesFor: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let parent = parent else { return }

        // Save known characteristics for later usage by UUID
        parent.registerCharacteristics(service.characteristics ?? [])

        parent.eventSubscriptions.receive(.discoveredCharacteristics(service, service.characteristics ?? [], error))
        parent.delegate?.peripheral(parent, didDiscoverCharacteristicsFor: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard let parent = parent else { return }
        parent.eventSubscriptions.receive(.discoveredDescriptors(characteristic, characteristic.descriptors ?? [], error))
        parent.delegate?.peripheral(parent, didDiscoverDescriptorsFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let parent = parent else { return }

        if let error {
            parent.responseMap.receive(key: characteristic.uuid, withValue: .failure(error))
        } else {
            // A read that succeeds without a value still has to be reported, or whoever
            // asked for it waits forever
            parent.responseMap.receive(key: characteristic.uuid, withValue: .success(characteristic.value ?? Data()))
        }

        parent.delegate?.peripheral(parent, didUpdateValueFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard let parent = parent else { return }

        if let error {
            parent.descriptorMap.receive(key: descriptor.uuid, withValue: .failure(error))
        } else {
            parent.descriptorMap.receive(key: descriptor.uuid, withValue: .success(descriptor.value))
        }

        parent.delegate?.peripheral(parent, didUpdateValueFor: descriptor, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let parent = parent else { return }

        parent.writeMap.receive(key: characteristic.uuid, withValue: error)
        parent.delegate?.peripheral(parent, didWriteValueFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        guard let parent = parent else { return }

        parent.writeMap.receive(key: descriptor.uuid, withValue: error)
        parent.delegate?.peripheral(parent, didWriteValueFor: descriptor, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let parent = parent else { return }
        parent.eventSubscriptions.receive(.updateNotificationState(characteristic, error))
        parent.delegate?.peripheral(parent, didUpdateNotificationStateFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard let parent = parent else { return }
        parent.eventSubscriptions.receive(.readRSSI(RSSI, error))
        parent.delegate?.peripheral(parent, didReadRSSI: RSSI, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices services: [CBService]) {
        guard let parent = parent else { return }
        parent.delegate?.peripheral(parent, didModifyServices: services)
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        guard let parent = parent else { return }
        parent.delegate?.peripheralDidUpdateName(parent)
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let parent = parent else { return }
        parent.eventSubscriptions.receive(.didOpenL2CAPChannel(channel, error))
        parent.delegate?.peripheral(parent, didOpen: channel, error: error)
    }
}
