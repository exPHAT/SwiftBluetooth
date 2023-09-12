import Foundation
import CoreBluetooth

internal enum PeripheralEvent {
    case discoveredServices([CBService], Error?)
    case discoveredCharacteristics(CBService, [CBCharacteristic], Error?)
    case discoveredDescriptors(CBCharacteristic, [CBDescriptor], Error?)
    case readRSSI(NSNumber, Error?)
    case didOpenL2CAPChannel(CBL2CAPChannel?, Error?)
}
