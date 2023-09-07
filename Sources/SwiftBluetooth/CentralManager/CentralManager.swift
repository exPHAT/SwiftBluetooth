import Foundation
import CoreBluetooth

public enum CentralEvent {
    case stateUpdated(CBManagerState)
    case discovered(Peripheral, [String: Any], NSNumber)
    case connected(Peripheral)
    case disconnected(Peripheral)
    case failToConnect(Peripheral)
}

public class CentralManager: NSObject {
    internal var centralManager: CBCentralManager
    private lazy var wrappedDelegate: CentralManagerDelegateWrapper = .init(parent: self)

    internal var eventSubscriptions = AsyncSubscriptionQueue<CentralEvent>()
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

    public init(delegate: CentralManagerDelegate? = nil, queue: DispatchQueue? = nil, options: [String: Any]? = nil) {
        self.delegate = delegate
        centralManager = .init(delegate: nil, queue: queue, options: options)
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
}

// Callback-based APIs
public extension CentralManager {
    func waitUntilReady(completionHandler: @escaping () -> Void) {
        eventSubscriptions.queue { event, done in
            if case .stateUpdated(let state) = event,
               state == .poweredOn {

                completionHandler()
                done()
            }
        }
    }

    func connect(_ peripheral: Peripheral, options: [String: Any]? = nil, completionHandler: @escaping () -> Void) {
        eventSubscriptions.queue { event, done in
            if case .connected(let connectedPeripheral) = event,
               connectedPeripheral.cbPeripheral == peripheral.cbPeripheral {

                completionHandler()
                done()
            }
        }

        connect(peripheral, options: options)
    }

    func scanForPeripherals(withServices services: [CBUUID]? = nil, options: [String: Any]? = nil, onPeripheralFound: @escaping (Peripheral) -> Void) -> AsyncEventSubscription<CentralEvent> {
        let subscription = eventSubscriptions.queue { event, _ in
            if case .discovered(let peripheral, _, _) = event {
                onPeripheralFound(peripheral)
            }
        }

        centralManager.scanForPeripherals(withServices: services, options: options)

        return subscription
    }
}

// Async wrappers around callback APIs
public extension CentralManager {
    func waitUntilReady() async {
        await withCheckedContinuation { cont in
            self.waitUntilReady {
                cont.resume()
            }
        }
    }

    func connect(_ peripheral: Peripheral, options: [String: Any]? = nil) async {
        await withCheckedContinuation { cont in
            self.connect(peripheral, options: options) {
                cont.resume()
            }
        }
    }

//    // TODO: Mark these as @available and have a non-returning version without an EventStream
//    @discardableResult // Traditionally this API will not return anything
//    func scanForPeripherals(withServices services: [CBUUID]? = nil, options: [String: Any]? = nil) -> AsyncStream<Peripheral> {
//        .init { cont in
//            let subscription = self.scanForPeripherals(withServices: services, options: options) { peripheral in
//                cont.yield(peripheral)
//            }
//
//            cont.onTermination = { _ in
//                subscription.cancel()
//            }
//        }
//    }
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
        centralManager.stopScan()
    }
}
