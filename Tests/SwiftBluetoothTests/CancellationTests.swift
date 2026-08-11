import XCTest
@testable import CoreBluetoothMock
@testable import SwiftBluetoothMock

/// Exercises the machinery that bridges the completion-handler API to `async`,
/// which has to resume its continuation exactly once no matter how the operation,
/// the timeout and the cancellation interleave.
final class CancellableContinuationTests: XCTestCase {
    private struct SpyTask: CancellableTask {
        let onCancel: () -> Void

        func cancel() {
            onCancel()
        }
    }

    func testReturnsResultWhenNotCancelled() async throws {
        let value = try await withCancellableContinuation { (completion: @escaping (Result<Int, Error>) -> Void) in
            completion(.success(7))
            return SpyTask { }
        }

        XCTAssertEqual(value, 7)
    }

    func testThrowsOperationFailure() async {
        do {
            _ = try await withCancellableContinuation { (completion: @escaping (Result<Int, Error>) -> Void) in
                completion(.failure(PeripheralError.unknown))
                return SpyTask { }
            }

            XCTFail("Should propagate the operation's error")
        } catch {
            XCTAssertEqual(error as? PeripheralError, .unknown)
        }
    }

    // Timeouts, disconnections and delegate callbacks can all report the same operation,
    // and resuming a continuation twice is fatal
    func testLaterResultsAreIgnored() async throws {
        let value = try await withCancellableContinuation { (completion: @escaping (Result<Int, Error>) -> Void) in
            completion(.success(1))
            completion(.success(2))
            completion(.failure(PeripheralError.unknown))
            return SpyTask { }
        }

        XCTAssertEqual(value, 1)
    }

    func testCancellingPendingOperationThrowsAndCancelsTheWork() async throws {
        let started = expectation(description: "operation registered")
        let cancelled = expectation(description: "operation cancelled")
        let extraWorkRan = expectation(description: "extra cancellation work ran")

        let task = Task {
            try await withCancellableContinuation {
                extraWorkRan.fulfill()
            } register: { (_: @escaping (Result<Int, Error>) -> Void) in
                started.fulfill()
                // Never completes, so only cancellation can end it
                return SpyTask { cancelled.fulfill() }
            }
        }

        await fulfillment(of: [started], timeout: 5)
        task.cancel()

        await fulfillment(of: [cancelled, extraWorkRan], timeout: 5)

        do {
            _ = try await task.value
            XCTFail("Should throw when cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    // Cancelling before the operation is ever registered shouldn't start it, or hang
    func testCancellingBeforeStartingNeverRegisters() async throws {
        let registered = expectation(description: "operation registered")
        registered.isInverted = true

        let task = Task {
            // Give the cancellation time to land first
            try await Task.sleep(nanoseconds: 200_000_000)

            return try await withCancellableContinuation { (_: @escaping (Result<Int, Error>) -> Void) in
                registered.fulfill()
                return SpyTask { }
            }
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Should throw when cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        await fulfillment(of: [registered], timeout: 1)
    }

    func testResultArrivingAfterCancellationIsIgnored() async throws {
        let completionBox = CompletionBox()
        let started = expectation(description: "operation registered")

        let task = Task {
            try await withCancellableContinuation { (completion: @escaping (Result<Int, Error>) -> Void) in
                completionBox.store(completion)
                started.fulfill()
                return SpyTask { }
            }
        }

        await fulfillment(of: [started], timeout: 5)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Should throw when cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        // Would trap if it reached the already-resumed continuation
        completionBox.complete(with: .success(1))
    }

    private final class CompletionBox {
        private let lock = NSLock()
        private var completion: ((Result<Int, Error>) -> Void)?

        func store(_ completion: @escaping (Result<Int, Error>) -> Void) {
            lock.lock()
            defer { lock.unlock() }

            self.completion = completion
        }

        func complete(with result: Result<Int, Error>) {
            lock.lock()
            let completion = self.completion
            lock.unlock()

            completion?(result)
        }
    }
}

final class OperationCancellationTests: CentralPeripheralTestCase {
    // Whether or not the read wins the race against the cancellation, the subscriptions
    // it registered have to be gone afterwards
    func testCancellingReadLeavesNoSubscriptions() async throws {
        try await central.wait(for: .poweredOn)
        peripheral = try await central.scanForPeripherals().first!
        try await central.connect(peripheral, timeout: connectionTimeout)

        for service in try await peripheral.discoverServices() {
            _ = try await peripheral.discoverCharacteristics(for: service)
        }

        let characteristic = try XCTUnwrap(peripheral.characteristic(for: .firstChar))

        for _ in 0..<25 {
            let task = Task {
                try await peripheral.readValue(for: characteristic)
            }

            task.cancel()

            do {
                _ = try await task.value
            } catch {
                XCTAssertTrue(error is CancellationError, "Expected cancellation, got \(error)")
            }
        }

        // Let anything still in flight drain
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(peripheral.responseMap.isEmpty)
        XCTAssertTrue(peripheral.eventSubscriptions.isEmpty)
    }

    func testCancellingDiscoverServicesLeavesNoSubscriptions() async throws {
        try await central.wait(for: .poweredOn)
        peripheral = try await central.scanForPeripherals().first!
        try await central.connect(peripheral, timeout: connectionTimeout)

        for _ in 0..<25 {
            let task = Task {
                try await peripheral.discoverServices()
            }

            task.cancel()

            do {
                _ = try await task.value
            } catch {
                XCTAssertTrue(error is CancellationError, "Expected cancellation, got \(error)")
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(peripheral.eventSubscriptions.isEmpty)
    }

    // Cancelling a callback operation used to drop the handler on the floor, leaving
    // the caller with no idea the work had stopped. It has to be reported either side
    // of registration, or the behaviour depends on timing the caller can't see.
    func testCancellingCallbackOperationBeforeItRegistersReportsCancellation() async throws {
        try await connectPeripheral()

        let reported = expectation(description: "completion handler reported cancellation")

        // Cancelled before the operation reaches the event queue and registers anything
        let task = peripheral.discoverServices { [self] result in
            assertCancelled(result, reported)
        }

        task.cancel()

        await fulfillment(of: [reported], timeout: 5)
    }

    func testCancellingCallbackOperationAfterItRegistersReportsCancellation() async throws {
        try await connectPeripheral()

        let reported = expectation(description: "completion handler reported cancellation")

        let task = peripheral.discoverServices { [self] result in
            assertCancelled(result, reported)
        }

        // Let the operation register its subscriptions before cancelling
        peripheral.eventQueue.sync { }

        task.cancel()

        await fulfillment(of: [reported], timeout: 5)
    }

    private func connectPeripheral() async throws {
        try await central.wait(for: .poweredOn)
        peripheral = try await central.scanForPeripherals().first!
        try await central.connect(peripheral, timeout: connectionTimeout)
    }

    private func assertCancelled<T>(_ result: Result<T, Error>, _ reported: XCTestExpectation) {
        switch result {
        case .success:
            XCTFail("Should not have completed after cancelling")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Expected cancellation, got \(error)")
            reported.fulfill()
        }
    }
}
