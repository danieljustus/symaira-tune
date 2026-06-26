import Foundation

/// Protocol abstracting network operations for testability.
public protocol NetworkServiceProtocol: Sendable {
    /// Fetches data from a URL.
    func fetchData(from url: URL) async throws -> (Data, URLResponse)
}

/// Production implementation using URLSession.
public struct URLSessionNetworkService: NetworkServiceProtocol {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
}
