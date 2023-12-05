import Foundation
import CoreBluetooth

extension Peripheral {
    public struct DiscoveryInfo {
        public var RSSI: Int
        public var advertisementData: AdvertisementData

        init(RSSI: NSNumber, advertisementData: [String : Any]) {
            self.RSSI = Int(truncating: RSSI)
            self.advertisementData = .init(data: advertisementData)
        }

        public struct AdvertisementData {
            private(set) var data: [String : Any]

            subscript(key: String) -> Any? {
                data[key]
            }

            public var localName: String? {
                data[CBAdvertisementDataLocalNameKey] as? String
            }

            public var manufacturerData: Data? {
                data[CBAdvertisementDataManufacturerDataKey] as? Data
            }

            public var serviceData: [CBUUID : Data]? {
                data[CBAdvertisementDataServiceDataKey] as? [CBUUID : Data]
            }

            public var serviceUUIDs: [CBUUID]? {
                data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
            }

            public var overflowServiceUUIDs: [CBUUID]? {
                data[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]
            }

            public var txPowerLevel: Int? {
                guard let value = data[CBAdvertisementDataTxPowerLevelKey] as? NSNumber else { return nil }

                return Int(truncating: value)
            }

            public var isConnectable: Bool? {
                guard let value = data[CBAdvertisementDataIsConnectable] as? NSNumber else { return nil }

                return Bool(truncating: value)
            }

            public var solicitedServiceUUIDs: [CBUUID]? {
                data[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]
            }
        }
    }
}
