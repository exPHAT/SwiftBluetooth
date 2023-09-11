import Foundation

public extension AsyncStream {
    var first: Element? {
        get async {
            await first(where: { _ in true })
        }
    }
}

