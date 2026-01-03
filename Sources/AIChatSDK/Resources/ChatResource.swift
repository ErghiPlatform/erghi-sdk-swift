import Foundation
import Alamofire

/// Chat resource for AI Chat SDK
public class ChatResource {
    private let config: AIChatConfig
    private let session: Session
    private let auth: AuthResource
    
    init(config: AIChatConfig, session: Session, auth: AuthResource) {
        self.config = config
        self.session = session
        self.auth = auth
    }
    
    /// Get conversation by ID
    public func getConversation(_ id: String) async throws -> Conversation {
        return try await session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(id)"),
            method: .get,
            headers: headers
        )
        .validate()
        .serializingDecodable(Conversation.self, decoder: dateDecoder)
        .value
    }
    
    /// Create a new conversation
    public func createConversation(
        widgetId: String,
        metadata: [String: AnyCodable]? = nil
    ) async throws -> Conversation {
        return try await session.request(
            config.apiURL.appendingPathComponent("/api/conversations"),
            method: .post,
            parameters: [
                "widgetId": widgetId,
                "metadata": metadata as Any
            ],
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
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
        return try await session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(conversationId)/messages"),
            method: .get,
            parameters: [
                "page": page,
                "limit": limit
            ],
            headers: headers
        )
        .validate()
        .serializingDecodable(PaginatedResponse<Message>.self, decoder: dateDecoder)
        .value
    }
    
    /// Send a message
    public func sendMessage(
        conversationId: String,
        request: SendMessageRequest
    ) async throws -> Message {
        return try await session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(conversationId)/messages"),
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
        .validate()
        .serializingDecodable(Message.self, decoder: dateDecoder)
        .value
    }
    
    /// Mark messages as read
    public func markAsRead(conversationId: String) async throws {
        _ = try await session.request(
            config.apiURL.appendingPathComponent("/api/conversations/\(conversationId)/read"),
            method: .put,
            headers: headers
        )
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
