import Foundation
import CoreBluetooth

public class CentralManager: NSObject {
    internal var centralManager: CBCentralManager
    private lazy var wrappedDelegate: CentralManagerDelegateWrapper = { .init(parent: self) }()

    private var peripheralMap: [UUID: Peripheral] = [:]

    // MARK: - CBCentralManager properties

    public var delegate: CentralManagerDelegate? // Accessed from wrappedDelegate directly
    public var state: CBManagerState { centralManager.state }
    public var isScanning: Bool { centralManager.isScanning }
    public var authorization: CBManagerAuthorization { centralManager.authorization }

    // MARK: - CBCentralManager initializers

    override init() {
        centralManager = .init()
        super.init()
        
        centralManager.delegate = wrappedDelegate
    }

    public init(delegate: CentralManagerDelegate?, queue: DispatchQueue? = nil, options: [String: Any]? = nil) {
        self.delegate = delegate
        centralManager = .init(delegate: nil, queue: queue, options: options)
        super.init()

        centralManager.delegate = wrappedDelegate

    }

    // MARK: - CBCentralManager methods

    public func connect(_ peripheral: Peripheral, options: [String: Any]? = nil) {
        centralManager.connect(peripheral.cbPeripheral, options: options)
    }

    public func cancelPeripheralConnection(_ peripheral: Peripheral) {
        centralManager.cancelPeripheralConnection(peripheral.cbPeripheral)
    }

    public func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [Peripheral] {
        centralManager.retrieveConnectedPeripherals(withServices: services).map(peripheral(_:))
    }

    public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [Peripheral] {
        centralManager.retrievePeripherals(withIdentifiers: identifiers).map(peripheral(_:))
    }

    public func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]? = nil) {
        centralManager.scanForPeripherals(withServices: services, options: options)
    }

    public func stopScan() {
        centralManager.stopScan()
    }

    // MARK: - Internal

    internal func peripheral(_ cbPeripheral: CBPeripheral) -> Peripheral {
        if let found = peripheralMap[cbPeripheral.identifier] {
            return found
        }

        // Save peripheral for later to recycle the object (might remove this to avoid ARC not deallocating)
        peripheralMap[cbPeripheral.identifier] = Peripheral(cbPeripheral)
        return peripheral(cbPeripheral)
    }
}
