import Foundation
import Alamofire
import Starscream
import Combine

/// Main AI Chat SDK Client
public class AIChatClient {
    public let config: AIChatConfig
    public let auth: AuthResource
    public let chat: ChatResource
    
    private let session: Session
    private var webSocket: WebSocket?
    private let messageSubject = PassthroughSubject<Message, Never>()
    
    /// Stream of real-time messages
    public var messagePublisher: AnyPublisher<Message, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    /// Check if WebSocket is connected
    public private(set) var isConnected = false
    
    public init(config: AIChatConfig) {
        self.config = config
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.timeout
        self.session = Session(configuration: configuration)
        
        self.auth = AuthResource(config: config, session: session)
        self.chat = ChatResource(config: config, session: session, auth: auth)
    }
    
    /// Connect to WebSocket for real-time updates
    public func connectWebSocket() {
        var request = URLRequest(url: config.websocketURL.appendingPathComponent("/hubs/chat"))
        
        if let apiKey = config.apiKey {
            request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        } else if let accessToken = auth.accessToken {
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
}

// MARK: - WebSocketDelegate

extension AIChatClient: WebSocketDelegate {
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
