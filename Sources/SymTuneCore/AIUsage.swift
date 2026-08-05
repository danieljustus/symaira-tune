import Foundation

// MARK: - AI usage snapshot model

/// Unit of an AI usage meter. Different providers meter tokens, requests,
/// credits, or spending in a currency; the normalized model keeps them apart.
public enum AIUsageUnit: Codable, Sendable, Equatable {
    case tokens
    case requests
    case credits
    case currency(String)
    case percent

    /// Human-readable unit label for tables and CLI output.
    public var unitLabel: String {
        switch self {
        case .tokens: return "tokens"
        case .requests: return "requests"
        case .credits: return "credits"
        case .currency(let code): return code
        case .percent: return "%"
        }
    }
}

/// One normalized usage meter (e.g. "this session", "this week", "credits").
public struct AIUsageMeter: Codable, Sendable, Equatable {
    public let label: String
    public let used: Decimal?
    public let limit: Decimal?
    public let unit: AIUsageUnit
    /// When this meter resets (shown as a countdown in the UI), if known.
    public let resetsAt: Date?

    public init(
        label: String,
        used: Decimal? = nil,
        limit: Decimal? = nil,
        unit: AIUsageUnit,
        resetsAt: Date? = nil
    ) {
        self.label = label
        self.used = used
        self.limit = limit
        self.unit = unit
        self.resetsAt = resetsAt
    }
}

/// Normalized view of one provider's AI usage, mapping the different provider
/// semantics (5h session windows, weekly quotas, credits, currency spend) onto
/// a common shape.
public struct AIUsageSnapshot: Codable, Sendable, Equatable {
    public let providerID: String
    public let meters: [AIUsageMeter]
    /// Remaining balance for balance-style providers (e.g. credits).
    public let balance: Decimal?
    public let currency: String?
    public let fetchedAt: Date
    /// Which fallback produced the data (`oauth`, `cli`, `web`, `api`,
    /// `local`). Shown in UI and CLI so a brittle active path stays visible.
    public let source: String

    /// Seconds since the snapshot was fetched. Computed at read time so
    /// consumers always see the true age.
    public var staleness: TimeInterval { Date().timeIntervalSince(fetchedAt) }

    private enum CodingKeys: String, CodingKey {
        // `providerId` (not `providerID`): the JSON encoder/decoder snake_case
        // strategies normalize `providerID` → `provider_id` → `providerId`,
        // so the stored key must round-trip through that exact pair.
        case providerID = "providerId"
        case meters
        case balance
        case currency
        case fetchedAt
        case source
    }

    public init(
        providerID: String,
        meters: [AIUsageMeter],
        balance: Decimal? = nil,
        currency: String? = nil,
        fetchedAt: Date = Date(),
        source: String
    ) {
        self.providerID = providerID
        self.meters = meters
        self.balance = balance
        self.currency = currency
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// A copy with the source tag replaced — used by the strategy chain so
    /// the snapshot always reports which fallback actually produced it.
    public func taggingSource(_ newSource: String) -> AIUsageSnapshot {
        AIUsageSnapshot(
            providerID: providerID,
            meters: meters,
            balance: balance,
            currency: currency,
            fetchedAt: fetchedAt,
            source: newSource
        )
    }
}

// MARK: - Provider contract

/// One ordered fallback strategy of a provider. Strategies run in order and
/// the first success wins; failures are collected, not swallowed.
public protocol AIUsageStrategy: Sendable {
    /// Human-readable source tag (`oauth`, `cli`, `web`, `api`, `local`).
    var source: String { get }
    func fetch() async throws -> AIUsageSnapshot
}

/// A usage provider: the contract every provider issue implements against.
public protocol AIUsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Whether the provider has usable credentials. Unconfigured providers
    /// are reported as "not set up", never as an error.
    var isConfigured: Bool { get }
    /// Ordered fallback strategies; the first success is the snapshot.
    var strategies: [any AIUsageStrategy] { get }
    func fetch() async throws -> AIUsageSnapshot
}

public extension AIUsageProvider {
    /// Default implementation: run the fallback chain.
    func fetch() async throws -> AIUsageSnapshot {
        try await AIUsageStrategyChain.run(strategies)
    }
}

// MARK: - Strategy chain

/// Runs a provider's ordered strategies, collecting partial failures.
public enum AIUsageStrategyChain {
    /// Return the first successful snapshot, tagged with the winning
    /// strategy's source. When every strategy fails, throw
    /// ``AIUsageError/chainFailed(_:)`` carrying all partial errors.
    public static func run(_ strategies: [any AIUsageStrategy]) async throws -> AIUsageSnapshot {
        var failures: [String] = []
        for strategy in strategies {
            do {
                let snapshot = try await strategy.fetch()
                return snapshot.taggingSource(strategy.source)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        throw AIUsageError.chainFailed(failures)
    }
}

// MARK: - Errors

public enum AIUsageError: Error, Sendable, CustomStringConvertible {
    case unknownProvider(String)
    case notConfigured(String)
    case timedOut(String)
    case rateLimited(String, retryAfter: TimeInterval?)
    /// Every fallback strategy failed; the array carries each partial error
    /// (already redacted at the service boundary).
    case chainFailed([String])
    /// An error whose description has been secret-redacted before leaving
    /// the service (no token material may reach logs, history, or the UI).
    case redacted(String)

    public var description: String {
        switch self {
        case .unknownProvider(let id):
            return "unknown AI usage provider '\(id)'"
        case .notConfigured(let id):
            return "AI usage provider '\(id)' is not configured"
        case .timedOut(let detail):
            return "AI usage provider timed out: \(detail)"
        case .rateLimited(let id, let retryAfter):
            if let retryAfter {
                return "AI usage provider '\(id)' is rate limited; retry in \(Int(retryAfter.rounded()))s"
            }
            return "AI usage provider '\(id)' is rate limited"
        case .chainFailed(let failures):
            let joined = failures.joined(separator: "; ")
            return "all AI usage fallbacks failed: \(joined)"
        case .redacted(let detail):
            return detail
        }
    }
}

// MARK: - LocalizedError

extension AIUsageError: LocalizedError {
    /// `localizedDescription` must carry the same meaningful text as
    /// `description` — the generic NSError fallback ("The operation couldn't
    /// be completed") would hide every provider detail from logs and users.
    public var errorDescription: String? { description }
}
