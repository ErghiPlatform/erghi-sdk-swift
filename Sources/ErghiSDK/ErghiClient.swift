import Foundation
import Alamofire
import Starscream
import Combine

/// Main Erghi SDK Client
public class ErghiClient {
    public let config: ErghiConfig
    public let auth: AuthResource
    public private(set) lazy var chat: ChatResource = ChatResource(
        config: config, session: session, auth: auth
    ) { [weak self] in
        self?.visitorId
    }
    
    private let session: Session
    private var webSocket: WebSocket?
    private let messageSubject = PassthroughSubject<Message, Never>()
    
    public private(set) var visitorId: String?
    
    /// Stream of real-time messages
    public var messagePublisher: AnyPublisher<Message, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    /// Check if WebSocket is connected
    public private(set) var isConnected = false
    
    public init(config: ErghiConfig) {
        self.config = config
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.timeout
        
        let interceptor = M2MRequestInterceptor(config: config)
        self.session = Session(configuration: configuration, interceptor: interceptor)
        
        self.auth = AuthResource(config: config, session: session)
        
        interceptor.auth = auth
    }
    
    /// Connect to WebSocket for real-time updates
    public func connectWebSocket() {
        var request = URLRequest(url: config.websocketURL.appendingPathComponent("/hubs/chat"))
        
        if let apiKey = config.apiKey {
            request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        } else if let accessToken = auth.accessToken {
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        if let workspaceId = config.workspaceId {
            request.addValue(workspaceId, forHTTPHeaderField: "X-Workspace-Id")
        }
        
        if let accountId = config.accountId {
            request.addValue(accountId, forHTTPHeaderField: "X-Account-Id")
        }
        
        webSocket = WebSocket(request: request)
        webSocket?.delegate = self
        webSocket?.connect()
    }
    
    /// Disconnect WebSocket
    public func disconnectWebSocket() {
        webSocket?.disconnect()
        webSocket = nil
        isConnected = false
    }
    
    /// Send typing indicator
    public func sendTyping(conversationId: String) {
        guard isConnected, let webSocket = webSocket else { return }
        
        let data: [String: Any] = [
            "type": "typing",
            "conversationId": conversationId
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocket.write(string: jsonString)
        }
    }
    
    /// Join a conversation room
    public func joinConversation(_ conversationId: String) {
        guard isConnected, let webSocket = webSocket else { return }
        
        let data: [String: Any] = [
            "type": "join",
            "conversationId": conversationId
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocket.write(string: jsonString)
        }
    }
    
    /// Leave a conversation room
    public func leaveConversation(_ conversationId: String) {
        guard isConnected, let webSocket = webSocket else { return }
        
        let data: [String: Any] = [
            "type": "leave",
            "conversationId": conversationId
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocket.write(string: jsonString)
        }
    }
    
    /// Authenticate a visitor using a signed JWT from the customer's backend.
    public func authenticateVisitor(widgetId: String, jwtToken: String) async throws -> String {
        struct IdentityRequest: Encodable {
            let widgetId: String
            let jwtToken: String
        }
        
        struct IdentityResponse: Decodable {
            let visitorId: String?
            let VisitorId: String?
            
            var resolvedId: String? { visitorId ?? VisitorId }
        }
        
        let request = session.request(
            config.apiURL.appendingPathComponent("/api/conversations/identity"),
            method: .post,
            parameters: IdentityRequest(widgetId: widgetId, jwtToken: jwtToken),
            encoder: JSONParameterEncoder.default
        )
        
        let response = try await request
            .validate()
            .serializingDecodable(IdentityResponse.self)
            .value
            
        guard let vId = response.resolvedId else {
            throw ErghiError.authenticationFailed("Visitor ID not found in identity response.")
        }
        
        self.visitorId = vId
        return vId
    }
}

// MARK: - WebSocketDelegate

extension ErghiClient: WebSocketDelegate {
    public func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true
            if config.debug {
                print("WebSocket connected")
            }
            
        case .disconnected(let reason, let code):
            isConnected = false
            if config.debug {
                print("WebSocket disconnected: \(reason) (code: \(code))")
            }
            
        case .text(let string):
            handleWebSocketMessage(string)
            
        case .error(let error):
            isConnected = false
            if config.debug, let error = error {
                print("WebSocket error: \(error)")
            }
            
        default:
            break
        }
    }
    
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "message",
              let messageData = json["data"] as? [String: Any],
              let messageJson = try? JSONSerialization.data(withJSONObject: messageData) else {
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let message = try? decoder.decode(Message.self, from: messageJson) {
            messageSubject.send(message)
        }
    }
}
