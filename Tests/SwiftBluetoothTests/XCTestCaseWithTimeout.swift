import XCTest

class XCTestCaseWithTimeout: XCTestCase {
    var timeoutDuration: TimeInterval = 5
    private var timeoutTimer: Timer?

    override open func setUp() {
        self.timeoutTimer = .scheduledTimer(withTimeInterval: timeoutDuration, repeats: false) { _ in
            XCTFail()
        }
    }

    override open func tearDown() {
        timeoutTimer?.invalidate()
    }
}
