import Foundation
import CoreBluetooth

internal enum PeripheralEvent {
    case discoveredServices([CBService], Error?)
    case discoveredCharacteristics([CBCharacteristic], Error?)
}
