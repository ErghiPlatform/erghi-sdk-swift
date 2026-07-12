import Foundation
import Alamofire

/// Chat resource for Erghi SDK
public class ChatResource {
    private let config: ErghiConfig
    private let session: Session
    private let auth: AuthResource
    private let getVisitorId: (() -> String?)?
    
    init(config: ErghiConfig, session: Session, auth: AuthResource, getVisitorId: (() -> String?)? = nil) {
        self.config = config
        self.session = session
        self.auth = auth
        self.getVisitorId = getVisitorId
    }
    
    /// Get conversation by ID
    public func getConversation(_ id: String) async throws -> Conversation {
        let request = session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(id)"),
            method: .get,
            headers: headers
        )
        return try await request
            .validate()
            .serializingDecodable(Conversation.self, decoder: dateDecoder)
            .value
    }
    
    /// Create a new conversation
    public func createConversation(
        widgetId: String,
        metadata: [String: AnyCodable]? = nil
    ) async throws -> Conversation {
        var parameters: [String: Any] = [
            "widgetId": widgetId
        ]
        if let metadata = metadata {
            parameters["metadata"] = metadata
        }
        if let visitorId = getVisitorId?() {
            parameters["visitorId"] = visitorId
        }
        
        let request = session.request(
            config.apiURL.appendingPathComponent("/api/conversations"),
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers
        )
        return try await request
            .validate()
            .serializingDecodable(Conversation.self, decoder: dateDecoder)
            .value
    }
    
    /// Get messages for a conversation
    public func getMessages(
        conversationId: String,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> PaginatedResponse<Message> {
        let parameters: [String: Any] = [
            "page": page,
            "limit": limit
        ]
        let request = session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(conversationId)/messages"),
            method: .get,
            parameters: parameters,
            headers: headers
        )
        return try await request
            .validate()
            .serializingDecodable(PaginatedResponse<Message>.self, decoder: dateDecoder)
            .value
    }
    
    /// Send a message
    public func sendMessage(
        conversationId: String,
        request: SendMessageRequest
    ) async throws -> Message {
        let req = session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(conversationId)/messages"),
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
        return try await req
            .validate()
            .serializingDecodable(Message.self, decoder: dateDecoder)
            .value
    }
    
    /// Mark messages as read
    public func markAsRead(conversationId: String) async throws {
        let request = session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(conversationId)/read"),
            method: .put,
            headers: headers
        )
        _ = try await request
            .validate()
            .serializingData()
            .value
    }
    
    // MARK: - Private
    
    private var headers: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(.contentType("application/json"))
        
        if let apiKey = config.apiKey {
            headers.add(name: "X-API-Key", value: apiKey)
        } else if let accessToken = auth.accessToken {
            headers.add(.authorization(bearerToken: accessToken))
        }
        
        return headers
    }
    
    private var dateDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
