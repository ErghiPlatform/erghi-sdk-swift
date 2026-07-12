import Foundation

/// Configuration for Erghi SDK
public struct ErghiConfig: Sendable {
    /// Base API URL
    public let apiURL: URL
    
    /// WebSocket URL (optional, will be derived from apiURL if not provided)
    public let wsURL: URL?
    
    /// API Key (optional, can use JWT instead)
    public let apiKey: String?
    
    /// Client ID for M2M authentication
    public let clientId: String?
    
    /// Client Secret for M2M authentication
    public let clientSecret: String?
    
    /// Workspace ID
    public let workspaceId: String?
    
    /// Account ID
    public let accountId: String?
    
    /// Request timeout
    public let timeout: TimeInterval
    
    /// Enable debug logging
    public let debug: Bool
    
    public init(
        apiURL: URL,
        wsURL: URL? = nil,
        apiKey: String? = nil,
        clientId: String? = nil,
        clientSecret: String? = nil,
        workspaceId: String? = nil,
        accountId: String? = nil,
        timeout: TimeInterval = 30,
        debug: Bool = false
    ) {
        self.apiURL = apiURL
        self.wsURL = wsURL
        self.apiKey = apiKey
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.workspaceId = workspaceId
        self.accountId = accountId
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
