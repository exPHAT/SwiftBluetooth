import Foundation
import CoreBluetooth

public struct Characteristic: Hashable, Equatable, ExpressibleByStringLiteral {
    public var uuid: CBUUID

    init(_ uuidString: String) {
        self.uuid = .init(string: uuidString)
    }

    init(cbUuid: CBUUID) {
        self.uuid = cbUuid
    }

    public init(stringLiteral value: StringLiteralType) {
        self.uuid = .init(string: value)
    }
}
