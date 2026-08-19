import XCTest
@testable import SymTuneCore

// MARK: - Fake network

/// Scripted network seam: returns fixture data or a canned error.
final class FakeNetwork: NetworkServiceProtocol, @unchecked Sendable {
    var result: Result<(Data, URLResponse), Error>
    var lastRequest: URLRequest?

    init(result: Result<(Data, URLResponse), Error>) {
        self.result = result
    }

    func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await fetchData(from: URLRequest(url: url))
    }

    func fetchData(from request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return try result.get()
    }
}

// MARK: - Tests

final class OpenRouterUsageProviderTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://openrouter.ai/api/v1/auth/key")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: Parsing fixtures (no network)

    func testParsesCreditsResponse() async throws {
        let network = FakeNetwork(result: .success((try fixture("openrouter-credits"), httpResponse(200))))
        let strategy = OpenRouterAPIStrategy(
            apiKey: "sk-or-v1-test",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            network: network
        )

        let snapshot = try await strategy.fetch()

        XCTAssertEqual(snapshot.providerID, "openrouter")
        XCTAssertEqual(snapshot.source, "api")
        XCTAssertEqual(snapshot.currency, "USD")
        XCTAssertEqual(snapshot.balance, 42.75)
        XCTAssertTrue(snapshot.meters.contains { $0.label == "Key limit" })
        XCTAssertTrue(snapshot.meters.contains { $0.label == "Requests" })
    }

    func testParsesResponseWithoutLimit() async throws {
        let network = FakeNetwork(result: .success((try fixture("openrouter-no-limit"), httpResponse(200))))
        let strategy = OpenRouterAPIStrategy(
            apiKey: "sk-or-v1-test",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            network: network
        )

        let snapshot = try await strategy.fetch()

        XCTAssertEqual(snapshot.balance, nil)
        XCTAssertTrue(snapshot.meters.contains { $0.label == "Spend" })
        XCTAssertFalse(snapshot.meters.contains { $0.label == "Key limit" })
    }

    func testOmitsRequestsMeterWhenRateLimitIsNotReal() async throws {
        let network = FakeNetwork(result: .success((try fixture("openrouter-no-request-limit"), httpResponse(200))))
        let strategy = OpenRouterAPIStrategy(
            apiKey: "sk-or-v1-test",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            network: network
        )

        let snapshot = try await strategy.fetch()

        XCTAssertFalse(snapshot.meters.contains { $0.label == "Requests" })
    }

    func testKeepsRequestsMeterWhenRateLimitIsReal() async throws {
        let network = FakeNetwork(result: .success((try fixture("openrouter-credits"), httpResponse(200))))
        let strategy = OpenRouterAPIStrategy(
            apiKey: "sk-or-v1-test",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            network: network
        )

        let snapshot = try await strategy.fetch()

        let meter = snapshot.meters.first { $0.label == "Requests" }
        XCTAssertNotNil(meter)
        XCTAssertEqual(meter?.limit, 500)
    }

    func testProviderUnconfiguredWithoutKey() {
        let provider = OpenRouterUsageProvider(
            apiKey: "",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!
        )
        XCTAssertFalse(provider.isConfigured)
    }

    func testProviderConfiguredWithKey() {
        let provider = OpenRouterUsageProvider(
            apiKey: "sk-or-v1-abc",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!
        )
        XCTAssertTrue(provider.isConfigured)
    }

    // MARK: Errors never leak key material

    func testAuthErrorIsUnderstandableWithoutKeyMaterial() async throws {
        let network = FakeNetwork(result: .success(("nope".data(using: .utf8)!, httpResponse(401))))
        let strategy = OpenRouterAPIStrategy(
            apiKey: "sk-or-v1-secret-key-material",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            network: network
        )

        do {
            _ = try await strategy.fetch()
            XCTFail("expected an error")
        } catch let error as OpenRouterError {
            let message = error.errorDescription ?? ""
            XCTAssertTrue(message.lowercased().contains("api key"), message)
            XCTAssertFalse(message.contains("sk-or-v1"), "key material must never leak")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testNetworkErrorWrapsWithoutLeakingKey() async throws {
        struct Boom: Error {}
        let network = FakeNetwork(result: .failure(Boom()))
        let strategy = OpenRouterAPIStrategy(
            apiKey: "sk-or-v1-secret-key-material",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            network: network
        )

        do {
            _ = try await strategy.fetch()
            XCTFail("expected an error")
        } catch let error as OpenRouterError {
            XCTAssertTrue(error.errorDescription?.contains("request failed") == true)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testAuthorizationHeaderUsesBearerToken() async throws {
        let network = FakeNetwork(result: .success((try fixture("openrouter-credits"), httpResponse(200))))
        let strategy = OpenRouterAPIStrategy(
            apiKey: "sk-or-v1-test-key",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            network: network
        )

        _ = try await strategy.fetch()

        let auth = network.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(auth, "Bearer sk-or-v1-test-key")
        let title = network.lastRequest?.value(forHTTPHeaderField: "X-Title")
        XCTAssertEqual(title, "symtune")
    }
}
