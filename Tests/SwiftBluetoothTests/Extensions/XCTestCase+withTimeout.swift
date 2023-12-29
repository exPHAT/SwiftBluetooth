import XCTest

struct TimedOutError: Error {
    let file: StaticString
    let line: UInt
}

extension XCTestCase {
    @available(iOS 13, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
    func withTimeout<T>(
        _ seconds: TimeInterval = 5,
        asyncOperation: @escaping () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            var done = false
            let notYetCompleted = {
                let current = done
                done = true
                return !current
            }

            Task {
                do {
                    let result = try await asyncOperation()
                    guard notYetCompleted() else { return }

                    cont.resume(returning: result)
                } catch {
                    guard notYetCompleted() else { return }

                    cont.resume(throwing: error)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                guard notYetCompleted() else { return }

                let error = TimedOutError(file: file, line: line)
//                let issue = XCTIssue(type: .assertionFailure, compactDescription: "Test timed out", associatedError: error)
//                XCTAssert(false)
                XCTFail("Test Timed Out")
                cont.resume(throwing: error)
            }
        }
    }
}
