import Foundation

public class AsyncSubscription<Element>: AsyncSequence, Identifiable {
    public typealias AsyncIterator = AsyncStream<Element>.Iterator

    public let id = UUID()
    private let wrappedStream: AsyncStream<Element>

    

    init(_ build: @escaping (AsyncStream<Element>.Continuation) -> Void) {
        self.wrappedStream = .init { cont in
            build(cont)
        }
    }

    public func cancel() {
        
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        wrappedStream.makeAsyncIterator()
    }
}

extension AsyncSubscription: Equatable {
    public static func == (lhs: AsyncSubscription<Element>, rhs: AsyncSubscription<Element>) -> Bool {
        lhs.id == rhs.id
    }
}
