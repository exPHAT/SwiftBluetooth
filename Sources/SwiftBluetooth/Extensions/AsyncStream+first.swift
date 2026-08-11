import Foundation

// Convenience API for people interfacing with AsyncStream. Not sure why this isn't in Foundation by default...
public extension AsyncStream {
    var first: Element? {
        get async {
            await first(where: { _ in true })
        }
    }
}

public extension AsyncThrowingStream {
    /// The first element, or `nil` if the stream finished without producing one.
    ///
    /// Throws if the stream finished with an error — a scan ending because Bluetooth
    /// was switched off, for instance, rather than because nothing was found.
    var first: Element? {
        get async throws {
            try await first(where: { _ in true })
        }
    }
}
