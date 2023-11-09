import Foundation
import CoreBluetooth

public class CentralManager: NSObject {
    private(set) var centralManager: CBCentralManager
    private lazy var wrappedDelegate: CentralManagerDelegateWrapper = .init(parent: self)

    internal var eventSubscriptions = AsyncSubscriptionQueue<CentralManagerEvent>()
    private var peripheralMap: [UUID: Peripheral] = [:]
    internal var connectedPeripherals = Set<Peripheral>()

    // MARK: - CBCentralManager properties
    public var delegate: CentralManagerDelegate? // Accessed from wrappedDelegate directly
    public var state: CBManagerState { centralManager.state }
    public var isScanning: Bool { centralManager.isScanning }

    @available(iOS, deprecated: 13.1)
    public var authorization: CBManagerAuthorization { centralManager.authorization }


    // MARK: - CBCentralManager initializers
    override init() {
        centralManager = CBCentralManagerFactory.instance(delegate: nil, queue: nil, forceMock: true)
        super.init()
        
        centralManager.delegate = wrappedDelegate
    }

    public init(delegate: CentralManagerDelegate? = nil, queue: DispatchQueue? = nil, options: [String: Any]? = nil) {
        self.delegate = delegate
        centralManager = CBCentralManagerFactory.instance(delegate: nil, queue: queue, options: options, forceMock: true)
        super.init()

        centralManager.delegate = wrappedDelegate
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

    internal func removePeripheral(_ cbPeripheral: CBPeripheral) {
        peripheralMap.removeValue(forKey: cbPeripheral.identifier)
    }
}

// MARK: - CBCentralManager methods
public extension CentralManager {
    func connect(_ peripheral: Peripheral, options: [String: Any]? = nil) {
        centralManager.connect(peripheral.cbPeripheral, options: options)
    }

    func cancelPeripheralConnection(_ peripheral: Peripheral) {
        centralManager.cancelPeripheralConnection(peripheral.cbPeripheral)
    }

    func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [Peripheral] {
        centralManager.retrieveConnectedPeripherals(withServices: services).map(peripheral(_:))
    }

    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [Peripheral] {
        centralManager.retrievePeripherals(withIdentifiers: identifiers).map(peripheral(_:))
    }

    func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]? = nil) {
        centralManager.scanForPeripherals(withServices: services, options: options)
    }

    func stopScan() {
        eventSubscriptions.recieve(.stopScan)
        centralManager.stopScan()
    }
}
