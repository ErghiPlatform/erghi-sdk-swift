import Foundation

/// Configuration for AI Chat SDK
public struct AIChatConfig {
    /// Base API URL
    public let apiURL: URL
    
    /// WebSocket URL (optional, will be derived from apiURL if not provided)
    public let wsURL: URL?
    
    /// API Key (optional, can use JWT instead)
    public let apiKey: String?
    
    /// Request timeout
    public let timeout: TimeInterval
    
    /// Enable debug logging
    public let debug: Bool
    
    public init(
        apiURL: URL,
        wsURL: URL? = nil,
        apiKey: String? = nil,
        timeout: TimeInterval = 30,
        debug: Bool = false
    ) {
        self.apiURL = apiURL
        self.wsURL = wsURL
        self.apiKey = apiKey
        self.timeout = timeout
        self.debug = debug
    }
    
    /// Get WebSocket URL (derive from apiURL if not provided)
    public var websocketURL: URL {
        if let wsURL = wsURL {
            return wsURL
        }
        
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
        components.scheme = apiURL.scheme == "https" ? "wss" : "ws"
        return components.url!
    }
}
