import XCTest

struct TimedOutError: Error {
    let file: StaticString
    let line: UInt
}

extension XCTestCase {
    func withTimeout<T>(
        _ seconds: TimeInterval = 5,
        asyncOperation: @escaping () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            let lock = NSLock()
            var done = false
            let notYetCompleted = {
                lock.lock()
                defer { lock.unlock() }

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
                XCTFail("Test Timed Out", file: file, line: line)
                cont.resume(throwing: error)
            }
        }
    }
}
