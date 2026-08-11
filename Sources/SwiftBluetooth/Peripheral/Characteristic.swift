import Foundation
import CoreBluetooth

public struct Characteristic: Hashable, Equatable, ExpressibleByStringLiteral, Sendable {
    public var uuid: CBUUID

    public init(_ uuidString: String) {
        self.uuid = .init(string: uuidString)
    }

    public init(cbUuid: CBUUID) {
        self.uuid = cbUuid
    }

    public init(stringLiteral value: StringLiteralType) {
        self.uuid = .init(string: value)
    }
}
