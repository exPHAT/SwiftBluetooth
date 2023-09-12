import Foundation
import CoreBluetooth

internal enum PeripheralEvent {
    case discoveredServices([CBService], Error?)
    case discoveredCharacteristics([CBCharacteristic], Error?)
    case readRSSI(NSNumber, Error?)
    case didOpenL2CAPChannel(CBL2CAPChannel?, Error?)
}
