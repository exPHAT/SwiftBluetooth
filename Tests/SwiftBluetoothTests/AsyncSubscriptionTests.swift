import XCTest
@testable import SwiftBluetoothMock

final class AsyncSubscriptionQueueTests: XCTestCase {
    private var queue: DispatchQueue!

    override func setUp() {
        queue = DispatchQueue(label: "async-subscription-tests")
    }

    // A subscription has to be visible the moment `queue` returns, or an event delivered
    // from another thread in between can be missed entirely
    func testSubscriptionIsRegisteredSynchronously() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)

        XCTAssertTrue(subscriptions.isEmpty)
        subscriptions.queue { _, _ in }
        XCTAssertFalse(subscriptions.isEmpty)
    }

    func testRemoveReportsWhetherItRemoved() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)
        let subscription = subscriptions.queue { _, _ in }

        XCTAssertTrue(subscriptions.remove(subscription))
        XCTAssertFalse(subscriptions.remove(subscription))
    }

    func testCancellingTwiceOnlyRunsCompletionOnce() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)
        var completions = 0

        let subscription = subscriptions.queue { _, _ in } completion: {
            completions += 1
        }

        subscription.cancel()
        subscription.cancel()
        subscription.cancel()

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(subscriptions.isEmpty)
    }

    func testValuesAreDeliveredToEverySubscriber() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)
        let received = Locked([Int]())

        subscriptions.queue { value, _ in received.mutate { $0.append(value) } }
        subscriptions.queue { value, _ in received.mutate { $0.append(value) } }

        subscriptions.recieve(1)
        queue.sync { }

        XCTAssertEqual(received.value, [1, 1])
    }

    func testValuesAreDeliveredInOrder() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)
        let received = Locked([Int]())

        subscriptions.queue { value, _ in received.mutate { $0.append(value) } }

        for value in 0..<100 {
            subscriptions.recieve(value)
        }
        queue.sync { }

        XCTAssertEqual(received.value, Array(0..<100))
    }

    func testDoneStopsFurtherDelivery() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)
        let received = Locked([Int]())

        subscriptions.queue { value, done in
            received.mutate { $0.append(value) }
            done()
        }

        subscriptions.recieve(1)
        subscriptions.recieve(2)
        queue.sync { }

        XCTAssertEqual(received.value, [1])
        XCTAssertTrue(subscriptions.isEmpty)
    }

    // One subscriber cancelling another mid-delivery should stop that one from being called
    func testSubscriptionCancelledDuringDeliveryIsNotCalled() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)
        let received = Locked([String]())

        // Delivery runs in reverse registration order, so this one is called last
        subscriptions.queue { _, _ in received.mutate { $0.append("first") } }
        let second = subscriptions.queue { _, _ in received.mutate { $0.append("second") } }

        subscriptions.queue { _, _ in
            received.mutate { $0.append("third") }
            second.cancel()
        }

        subscriptions.recieve(1)
        queue.sync { }

        XCTAssertEqual(received.value, ["third", "first"])
    }

    func testConcurrentRegistrationKeepsEverySubscription() {
        let subscriptions = AsyncSubscriptionQueue<Int>(queue)
        let count = 500
        let received = Locked(0)

        DispatchQueue.concurrentPerform(iterations: count) { _ in
            subscriptions.queue { _, _ in received.mutate { $0 += 1 } }
        }

        subscriptions.recieve(1)
        queue.sync { }

        XCTAssertEqual(received.value, count)
    }
}

final class AsyncSubscriptionQueueMapTests: XCTestCase {
    private var queue: DispatchQueue!

    override func setUp() {
        queue = DispatchQueue(label: "async-subscription-map-tests")
    }

    func testValuesAreDeliveredByKey() {
        let subscriptions = AsyncSubscriptionQueueMap<String, Int>(queue)
        let received = Locked([String: Int]())

        subscriptions.queue(key: "a") { value, _ in received.mutate { $0["a"] = value } }
        subscriptions.queue(key: "b") { value, _ in received.mutate { $0["b"] = value } }

        subscriptions.recieve(key: "a", withValue: 1)
        queue.sync { }

        XCTAssertEqual(received.value, ["a": 1])
    }

    func testIsEmptyTracksNestedQueues() {
        let subscriptions = AsyncSubscriptionQueueMap<String, Int>(queue)

        XCTAssertTrue(subscriptions.isEmpty)

        let subscription = subscriptions.queue(key: "a") { _, _ in }
        XCTAssertFalse(subscriptions.isEmpty)

        subscription.cancel()
        XCTAssertTrue(subscriptions.isEmpty)
    }

    // Two threads registering the first subscription for the same key used to be able to
    // replace each other's queue, leaving one subscription unreachable
    func testConcurrentFirstRegistrationForSameKeyKeepsEverySubscription() {
        for _ in 0..<50 {
            let subscriptions = AsyncSubscriptionQueueMap<String, Int>(queue)
            let count = 32
            let received = Locked(0)

            DispatchQueue.concurrentPerform(iterations: count) { _ in
                subscriptions.queue(key: "shared") { _, _ in received.mutate { $0 += 1 } }
            }

            subscriptions.recieve(key: "shared", withValue: 1)
            queue.sync { }

            XCTAssertEqual(received.value, count)
        }
    }
}

final class NotifyingTrackerTests: XCTestCase {
    func testInternalSubscribersKeepNotificationsOn() {
        let tracker = NotifyingTracker<String>()

        tracker.addInternal(forKey: "a")
        tracker.addInternal(forKey: "a")

        XCTAssertTrue(tracker.removeInternal(forKey: "a"), "Should stay on while another subscriber remains")
        XCTAssertFalse(tracker.removeInternal(forKey: "a"), "Should turn off once the last subscriber leaves")
    }

    func testExternallyEnabledNotificationsSurviveInternalSubscribers() {
        let tracker = NotifyingTracker<String>()

        XCTAssertTrue(tracker.setExternal(true, forKey: "a"))
        tracker.addInternal(forKey: "a")

        XCTAssertTrue(tracker.removeInternal(forKey: "a"), "The external subscription still wants values")
    }

    func testRemovingMoreThanWasAddedDoesNotUnderflow() {
        let tracker = NotifyingTracker<String>()

        tracker.addInternal(forKey: "a")

        XCTAssertFalse(tracker.removeInternal(forKey: "a"))
        XCTAssertFalse(tracker.removeInternal(forKey: "a"))

        // A fresh subscriber has to bring it back on, not start from a negative count
        tracker.addInternal(forKey: "a")
        XCTAssertTrue(tracker.removeInternal(forKey: "a") == false)
    }
}

/// Minimal box so tests can mutate state from concurrent contexts without racing.
private final class Locked<Value> {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }

        return storage
    }

    func mutate(_ block: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        block(&storage)
    }
}
