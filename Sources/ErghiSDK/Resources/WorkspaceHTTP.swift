import Foundation
import Alamofire

/// Shared request plumbing for the workspace (admin / server-side) resources. The workspace
/// comes from the API key or access token, never from a parameter.
final class WorkspaceHTTP {
    private let config: ErghiConfig
    private let session: Session
    private let auth: AuthResource

    init(config: ErghiConfig, session: Session, auth: AuthResource) {
        self.config = config
        self.session = session
        self.auth = auth
    }

    /// Path segment for an id, percent-escaped so an id can never add path segments.
    static func seg(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    private var headers: HTTPHeaders {
        var headers = HTTPHeaders()
        if let accessToken = auth.accessToken {
            headers.add(.authorization(bearerToken: accessToken))
        } else if let apiKey = config.apiKey {
            headers.add(name: "X-API-Key", value: apiKey)
        }
        return headers
    }

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: config.apiURL)!.absoluteURL
    }

    func send<T: Decodable>(
        _ type: T.Type, _ method: HTTPMethod, _ path: String,
        query: [String: String] = [:]
    ) async throws -> T {
        try await session.request(
            url(path), method: method, parameters: query.isEmpty ? nil : query,
            encoding: URLEncoding.queryString, headers: headers
        )
        .validate()
        .serializingDecodable(T.self, decoder: Self.decoder)
        .value
    }

    func send<T: Decodable, B: Encodable>(
        _ type: T.Type, _ method: HTTPMethod, _ path: String, body: B
    ) async throws -> T {
        try await session.request(
            url(path), method: method, parameters: body,
            encoder: JSONParameterEncoder.default, headers: headers
        )
        .validate()
        .serializingDecodable(T.self, decoder: Self.decoder)
        .value
    }

    /// For calls that return no body (204).
    func sendVoid(_ method: HTTPMethod, _ path: String) async throws {
        _ = try await session.request(url(path), method: method, headers: headers)
            .validate()
            .serializingData()
            .value
    }

    // The server writes ISO 8601 with fractional seconds or without, and sometimes seven-digit
    // .NET ticks, which ISO8601DateFormatter cannot read: drop digits past milliseconds.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            if let dot = text.firstIndex(of: "."), let zone = text.lastIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }), dot < zone {
                let trimmed = String(text[..<dot]) + "." + String(text[text.index(after: dot)..<zone].prefix(3)) + String(text[zone...])
                if let date = fractional.date(from: trimmed) { return date }
            }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid date: \(text)")
        }
        return decoder
    }
}
