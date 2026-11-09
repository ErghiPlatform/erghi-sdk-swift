import Foundation
import Alamofire

/// Filters shared by insights summary, list and export. All optional.
///
/// `sentiment`: positive, neutral or negative. `outcome`: resolved_by_ai, resolved_by_agent,
/// handed_off_unresolved, abandoned or spam_or_empty. `minConfidence` is 0 to 1.
public struct InsightFilter: Equatable {
    public var from: Date?
    public var to: Date?
    public var channel: String?
    public var category: String?
    public var topic: String?
    public var sentiment: String?
    public var outcome: String?
    public var minConfidence: Double?

    public init(
        from: Date? = nil, to: Date? = nil, channel: String? = nil, category: String? = nil,
        topic: String? = nil, sentiment: String? = nil, outcome: String? = nil,
        minConfidence: Double? = nil
    ) {
        self.from = from
        self.to = to
        self.channel = channel
        self.category = category
        self.topic = topic
        self.sentiment = sentiment
        self.outcome = outcome
        self.minConfidence = minConfidence
    }

    func queryParameters() -> [String: String] {
        var query: [String: String] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let from = from { query["from"] = formatter.string(from: from) }
        if let to = to { query["to"] = formatter.string(from: to) }
        for (key, value) in [
            ("channel", channel), ("category", category), ("topic", topic),
            ("sentiment", sentiment), ("outcome", outcome),
        ] {
            if let value = value, !value.isEmpty { query[key] = value }
        }
        if let minConfidence = minConfidence { query["minConfidence"] = String(minConfidence) }
        return query
    }
}

public struct InsightCount: Codable, Equatable {
    public let key: String
    public let count: Int
}

public struct InsightSummary: Codable, Equatable {
    public let total: Int
    /// AI-resolved over conversations that needed a reply (spam/empty excluded); nil when none.
    public let aiResolvedRate: Double?
    public let outcomes: [InsightCount]
    public let sentiments: [InsightCount]
    public let categories: [InsightCount]
    public let topics: [InsightCount]
    public let languages: [InsightCount]
}

/// One classified conversation. Sentiments are Positive/Neutral/Negative; `outcome` is
/// ResolvedByAi, ResolvedByAgent, HandedOffUnresolved, Abandoned or SpamOrEmpty; `language` is a
/// BCP-47 tag; `stale` means it was reopened and is reclassified on its next close.
public struct InsightConversation: Codable, Equatable {
    public let conversationId: String
    public let topic: String
    public let category: String
    public let sentiment: String
    public let sentimentEnd: String
    public let outcome: String
    public let language: String
    public let summary: String
    public let confidence: Double
    public let classifiedAt: Date
    public let stale: Bool
}

public struct InsightPage: Codable, Equatable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let items: [InsightConversation]
}

/// Conversation Insights: topic, sentiment and outcome of finished conversations.
///
/// Needs the `view_insights` workspace permission (Owner and Admin roles), so use a signed-in
/// user's access token. API keys and client-credentials tokens get 403. An invalid filter is a
/// 400 with the code `invalid_filter`.
public class InsightsResource {
    private let config: ErghiConfig
    private let session: Session
    private let auth: AuthResource

    init(config: ErghiConfig, session: Session, auth: AuthResource) {
        self.config = config
        self.session = session
        self.auth = auth
    }

    /// Counts by outcome, sentiment, category, topic (top 20) and language, plus the AI-resolved rate.
    public func summary(_ filter: InsightFilter = InsightFilter()) async throws -> InsightSummary {
        try await session.request(
            config.apiURL.appendingPathComponent("/api/v1/insights/summary"),
            method: .get,
            parameters: filter.queryParameters(),
            encoding: URLEncoding.queryString,
            headers: headers
        )
        .validate()
        .serializingDecodable(InsightSummary.self, decoder: Self.decoder)
        .value
    }

    /// Classified conversations, newest first. `pageSize` is capped at 100 by the server.
    public func listConversations(
        _ filter: InsightFilter = InsightFilter(), page: Int? = nil, pageSize: Int? = nil
    ) async throws -> InsightPage {
        var parameters = filter.queryParameters()
        if let page = page { parameters["page"] = String(page) }
        if let pageSize = pageSize { parameters["pageSize"] = String(pageSize) }
        return try await session.request(
            config.apiURL.appendingPathComponent("/api/v1/insights/conversations"),
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.queryString,
            headers: headers
        )
        .validate()
        .serializingDecodable(InsightPage.self, decoder: Self.decoder)
        .value
    }

    /// The same rows as CSV (newest first, at most 10,000 rows). The data starts with a UTF-8
    /// byte-order mark so Excel reads Arabic correctly; write it to disk as is. Text fields that
    /// start with `= + - @` are prefixed with `'` so a spreadsheet will not run them as formulas.
    public func exportCSV(_ filter: InsightFilter = InsightFilter()) async throws -> Data {
        try await session.request(
            config.apiURL.appendingPathComponent("/api/v1/insights/export.csv"),
            method: .get,
            parameters: filter.queryParameters(),
            encoding: URLEncoding.queryString,
            headers: headers
        )
        .validate()
        .serializingData()
        .value
    }

    // MARK: - Private

    // A user's token first: an API key can never hold view_insights.
    private var headers: HTTPHeaders {
        var headers = HTTPHeaders()
        if let accessToken = auth.accessToken {
            headers.add(.authorization(bearerToken: accessToken))
        } else if let apiKey = config.apiKey {
            headers.add(name: "X-API-Key", value: apiKey)
        }
        return headers
    }

    // The server writes ISO 8601 with fractional seconds (2026-11-09T10:14:03.123456Z) or without.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            // Seven-digit .NET ticks are beyond ISO8601DateFormatter: drop digits past milliseconds.
            if let dot = text.firstIndex(of: "."), let zone = text.lastIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }), dot < zone {
                let trimmed = String(text[..<dot]) + "." + String(text[text.index(after: dot)..<zone].prefix(3)) + String(text[zone...])
                if let date = fractional.date(from: trimmed) { return date }
            }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid date: \(text)")
        }
        return decoder
    }
}
