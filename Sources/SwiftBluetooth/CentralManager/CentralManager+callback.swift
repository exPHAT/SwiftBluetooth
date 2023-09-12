import Foundation
import CoreBluetooth

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

    func connect(_ peripheral: Peripheral, options: [String: Any]? = nil, completionHandler: @escaping (Result<Peripheral, Error>) -> Void) {
        eventSubscriptions.queue { event, done in
            switch event {
            case .connected(let connected):
                guard connected == peripheral else { return }
                completionHandler(.success(peripheral))
            case .disconnected(let disconnected, let error):
                guard disconnected == peripheral else { return }
                completionHandler(.failure(error ?? CentralError.unknown))
            case .failToConnect(let failed, let error):
                guard failed == peripheral else { return }
                completionHandler(.failure(error ?? CentralError.unknown))
            default:
                return
            }

            done()
        }

        connect(peripheral, options: options)
    }

    func scanForPeripherals(withServices services: [CBUUID]? = nil, options: [String: Any]? = nil, onPeripheralFound: @escaping (Peripheral) -> Void) -> CancellableTask {
        let subscription = eventSubscriptions.queue { event, done in
            switch event {
            case .discovered(let peripheral, _, _):
                onPeripheralFound(peripheral)
            case .stopScan:
                done()
            default:
                break
            }
        } completion: { [weak self] in
            guard let self = self else { return }

//            Needs to only be called when `done()` is called as a cancellation, not a completion.
//            Maybe can also repurpose the idea of calling `done` as always being a completion?...
//
//            self.centralManager.stopScan()
        }

        centralManager.scanForPeripherals(withServices: services, options: options)

        return subscription
    }
}
