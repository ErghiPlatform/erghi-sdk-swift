import Foundation

/// Base error type for AI Chat SDK
public enum AIChatError: Error, LocalizedError {
    case authenticationFailed(String)
    case networkError(String)
    case invalidResponse(String)
    case notFound(String)
    case validationError(String)
    case webSocketError(String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .webSocketError(let message):
            return "WebSocket error: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}
