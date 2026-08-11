import Foundation
@preconcurrency import CoreBluetooth

extension Peripheral {
    /// What a peripheral told us about itself when it was discovered by a scan.
    public struct DiscoveryInfo {
        /// Signal strength at the moment of the advertisement, in decibels.
        public var rssi: Int

        /// The advertisement packet the peripheral sent.
        public var advertisementData: AdvertisementData

        init(rssi: NSNumber, advertisementData: [String : Any]) {
            self.rssi = Int(truncating: rssi)
            self.advertisementData = .init(data: advertisementData)
        }

        /// The contents of an advertisement packet.
        ///
        /// The named properties cover the keys CoreBluetooth documents. Anything else can be
        /// read by subscripting with a `CBAdvertisementData…` key.
        public struct AdvertisementData {
            private(set) var data: [String : Any]

            /// Reads a value straight out of the advertisement by its CoreBluetooth key.
            public subscript(key: String) -> Any? {
                data[key]
            }

            /// The peripheral's advertised name, which can differ from `peripheral.name`.
            public var localName: String? {
                data[CBAdvertisementDataLocalNameKey] as? String
            }

            public var manufacturerData: Data? {
                data[CBAdvertisementDataManufacturerDataKey] as? Data
            }

            public var serviceData: [CBUUID : Data] {
                data[CBAdvertisementDataServiceDataKey] as? [CBUUID : Data] ?? [:]
            }

            public var serviceUUIDs: [CBUUID] {
                data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            }

            public var overflowServiceUUIDs: [CBUUID] {
                data[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
            }

            /// Transmit power the peripheral advertised, which can be compared against
            /// ``Peripheral/DiscoveryInfo/rssi`` to estimate distance. `nil` when it didn't say.
            public var txPowerLevel: Int? {
                guard let value = data[CBAdvertisementDataTxPowerLevelKey] as? NSNumber else { return nil }

                return Int(truncating: value)
            }

            /// Whether the peripheral is advertising as connectable. `nil` when it didn't say.
            public var isConnectable: Bool? {
                guard let value = data[CBAdvertisementDataIsConnectable] as? NSNumber else { return nil }

                return Bool(truncating: value)
            }

            public var solicitedServiceUUIDs: [CBUUID] {
                data[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []
            }
        }
    }
}
