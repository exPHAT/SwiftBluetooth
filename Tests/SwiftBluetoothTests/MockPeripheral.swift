import Foundation
@testable import CoreBluetoothMock

private class ConnectablePeripheralDelegateSpec: CBMPeripheralSpecDelegate {
    var values: [CBMUUID: Data] = [:]

    func peripheralDidReceiveConnectionRequest(_ peripheral: CBMPeripheralSpec) -> Result<Void, Error> {
        .success(Void())
    }

    func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveReadRequestFor characteristic: CBMCharacteristicMock) -> Result<Data, Error> {
        .success(values[characteristic.uuid] ?? .init([0x00]))
    }

    func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveWriteCommandFor characteristic: CBMCharacteristicMock, data: Data) {
        values[characteristic.uuid] = data
    }

    func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveWriteRequestFor characteristic: CBMCharacteristicMock, data: Data) -> Result<Void, Error> {
        values[characteristic.uuid] = data

        return .success(Void())
    }

//    func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveSetNotifyRequest enabled: Bool, for characteristic: CBMCharacteristicMock) -> Result<Void, Error> {
//
//    }
}

let mockCharacteristics: [CBMCharacteristicMock] = [
    .init(type: CBMUUID(string: "00000000-0000-0000-0001-000000000001"),
          properties: [.write, .writeWithoutResponse, .read, .notify],
          descriptors: CBMClientCharacteristicConfigurationDescriptorMock()),
    .init(type: CBMUUID(string: "00000000-0000-0000-0001-000000000002"),
          properties: [.write, .read],
          descriptors: CBMClientCharacteristicConfigurationDescriptorMock()),
    .init(type: CBMUUID(string: "00000000-0000-0000-0002-000000000001"),
          properties: [.write],
          descriptors: CBMClientCharacteristicConfigurationDescriptorMock()),
    .init(type: CBMUUID(string: "00000000-0000-0000-0002-000000000002"),
          properties: [.read],
          descriptors: CBMClientCharacteristicConfigurationDescriptorMock()),
]

let mockServices: [CBMServiceMock] = [
    .init(type: CBMUUID(string: "00000000-0000-0000-0001-000000000000"),
          primary: true,
          characteristics: mockCharacteristics[0], mockCharacteristics[1]),
    .init(type: CBMUUID(string: "00000000-0000-0000-0002-000000000000"),
          primary: true,
          characteristics: mockCharacteristics[2], mockCharacteristics[2]),
]

let mockPeripheral = CBMPeripheralSpec.simulatePeripheral(identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                                                          proximity: .near)
    .advertising(advertisementData: [CBMAdvertisementDataLocalNameKey : "Test Device",
                                     CBMAdvertisementDataServiceUUIDsKey : mockServices.map(\.uuid),
                                     CBMAdvertisementDataIsConnectable : true as NSNumber],
                 withInterval: 0.1)
    .connectable(name: "Test Device",
                 services: mockServices,
                 delegate: ConnectablePeripheralDelegateSpec())
    .build()
