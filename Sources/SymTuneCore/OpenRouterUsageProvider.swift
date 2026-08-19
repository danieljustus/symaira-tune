import Foundation

// MARK: - OpenRouter provider

/// OpenRouter usage provider — the first vertical AI-usage provider.
///
/// Data source: the credits/key API at `https://openrouter.ai/api/v1`.
/// Authentication is a plain API key (`sk-or-v1-…`) read from the Keychain
/// (fallback: `OPENROUTER_API_KEY` environment variable). The key is never
/// stored in `config.toml` and never included in any error message.
public struct OpenRouterUsageProvider: AIUsageProvider, Sendable {
    public let id = "openrouter"
    public let displayName = "OpenRouter"

    /// Whether a usable API key is present. Unconfigured providers must
    /// report "not set up" instead of erroring.
    public var isConfigured: Bool { !apiKey.isEmpty }

    public var strategies: [any AIUsageStrategy] {
        [OpenRouterAPIStrategy(apiKey: apiKey, baseURL: baseURL, network: network)]
    }

    private let apiKey: String
    private let baseURL: URL
    private let network: any NetworkServiceProtocol

    /// - Parameters:
    ///   - apiKey: explicit key; defaults to Keychain lookup with
    ///     `OPENROUTER_API_KEY` fallback.
    ///   - baseURL: API base; defaults to the `OPENROUTER_API_URL`
    ///     environment override or `https://openrouter.ai/api/v1`.
    ///   - network: injectable network seam for tests.
    public init(
        apiKey: String? = nil,
        baseURL: URL? = nil,
        network: any NetworkServiceProtocol = URLSessionNetworkService()
    ) {
        let envKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        self.apiKey = apiKey ?? envKey ?? KeychainCredentials.read(
            service: "com.symaira.symtune",
            account: "openrouter-api-key"
        ) ?? ""
        let envURL = ProcessInfo.processInfo.environment["OPENROUTER_API_URL"]
            .flatMap(URL.init(string:))
        self.baseURL = baseURL ?? envURL ?? URL(string: "https://openrouter.ai/api/v1")!
        self.network = network
    }
}

// MARK: - Strategy

/// Fetches OpenRouter credit/usage state via the key endpoint.
///
/// `GET {base}/auth/key` with `Authorization: Bearer <apiKey>` returns the
/// key's label, total usage, limit, rate limits and free-tier flag.
public struct OpenRouterAPIStrategy: AIUsageStrategy, Sendable {
    public let source = "api"

    private let apiKey: String
    private let baseURL: URL
    private let network: any NetworkServiceProtocol

    public init(apiKey: String, baseURL: URL, network: any NetworkServiceProtocol) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.network = network
    }

    public func fetch() async throws -> AIUsageSnapshot {
        let endpoint = baseURL.appendingPathComponent("auth/key")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("symtune", forHTTPHeaderField: "X-Title")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await network.fetchData(from: request)
        } catch {
            throw OpenRouterError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw AIUsageError.rateLimited("openrouter", retryAfter: retryAfterSeconds(from: http))
            }
            // Deliberately no response body in the error: a gateway error
            // page can echo the request headers back (including the key).
            throw OpenRouterError.httpStatus(http.statusCode)
        }

        let payload: OpenRouterKeyResponse
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(OpenRouterKeyResponse.self, from: data)
        } catch {
            throw OpenRouterError.unparseable
        }

        let key = payload.data
        var meters: [AIUsageMeter] = []

        // Primary meter: spend against the key limit (USD).
        if let limit = key.limit {
            meters.append(AIUsageMeter(
                label: "Key limit",
                used: key.usage.map { Decimal($0) },
                limit: Decimal(limit),
                unit: .currency("USD"),
                resetsAt: key.usagePeriod?.endTime
            ))
        } else if let usage = key.usage {
            meters.append(AIUsageMeter(
                label: "Spend",
                used: Decimal(usage),
                limit: nil,
                unit: .currency("USD"),
                resetsAt: key.usagePeriod?.endTime
            ))
        }

        // Secondary meter: free-tier daily request rate limit.
        // OpenRouter reports `-1` (or other non-negative-free sentinels) when
        // no real request cap is configured; that carries no information, so
        // omit the meter entirely rather than rendering a bogus negative limit.
        if let rateLimit = key.rateLimit, let requests = rateLimit.requests, requests >= 0 {
            meters.append(AIUsageMeter(
                label: "Requests",
                used: nil,
                limit: Decimal(requests),
                unit: .requests,
                resetsAt: nil
            ))
        }

        return AIUsageSnapshot(
            providerID: "openrouter",
            meters: meters,
            balance: key.creditBalance.map { Decimal($0) },
            currency: "USD",
            fetchedAt: Date(),
            source: source
        )
    }
}

// MARK: - Response model

struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData
}

struct OpenRouterKeyData: Decodable {
    let label: String?
    let usage: Double?
    let limit: Double?
    let isFreeTier: Bool?
    let rateLimit: OpenRouterRateLimit?
    let usagePeriod: OpenRouterUsagePeriod?
    /// Total credits purchased; balance = credits - usage.
    let totalCredits: Double?

    var creditBalance: Double? {
        guard let totalCredits, let usage else { return nil }
        return totalCredits - usage
    }
}

struct OpenRouterRateLimit: Decodable {
    let requests: Int?
    let interval: String?
}

struct OpenRouterUsagePeriod: Decodable {
    let startTime: Date?
    let endTime: Date?
}

// MARK: - Rate limit parsing

/// Parses the `Retry-After` header's delta-seconds form (e.g. `"30"`);
/// `nil` when the header is absent or not a plain integer/decimal — the
/// HTTP-date form is not handled since 429 responses conventionally use
/// delta-seconds.
private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
    guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
    return TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines))
}

// MARK: - Errors

enum OpenRouterError: Error, LocalizedError {
    case network(String)
    case invalidResponse
    case httpStatus(Int)
    case unparseable

    var errorDescription: String? {
        switch self {
        case .network(let detail):
            return "OpenRouter request failed: \(detail)"
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        case .httpStatus(let code):
            if code == 401 || code == 403 {
                return "OpenRouter rejected the API key (HTTP \(code)). Check the key in the Keychain."
            }
            return "OpenRouter request failed with HTTP \(code)."
        case .unparseable:
            return "OpenRouter returned an unreadable response."
        }
    }
}
