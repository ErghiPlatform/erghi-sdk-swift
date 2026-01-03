import Foundation
import Alamofire

/// Authentication resource for AI Chat SDK
public class AuthResource {
    private let config: AIChatConfig
    private let session: Session
    
    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    
    init(config: AIChatConfig, session: Session) {
        self.config = config
        self.session = session
    }
    
    /// Register a new user
    public func register(_ request: RegisterRequest) async throws -> AuthResponse {
        let response = try await session.request(
            config.apiURL.appendingPathComponent("/api/auth/register"),
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
        .validate()
        .serializingDecodable(AuthResponse.self, decoder: dateDecoder)
        .value
        
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        
        return response
    }
    
    /// Login with email and password
    public func login(_ request: LoginRequest) async throws -> AuthResponse {
        let response = try await session.request(
            config.apiURL.appendingPathComponent("/api/auth/login"),
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
        .validate()
        .serializingDecodable(AuthResponse.self, decoder: dateDecoder)
        .value
        
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        
        return response
    }
    
    /// Refresh access token
    public func refresh() async throws -> AuthResponse {
        guard let refreshToken = refreshToken else {
            throw AIChatError.authenticationFailed("No refresh token available")
        }
        
        let response = try await session.request(
            config.apiURL.appendingPathComponent("/api/auth/refresh"),
            method: .post,
            parameters: RefreshRequest(refreshToken: refreshToken),
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
        .validate()
        .serializingDecodable(AuthResponse.self, decoder: dateDecoder)
        .value
        
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        
        return response
    }
    
    /// Get current user
    public func me() async throws -> User {
        return try await session.request(
            config.apiURL.appendingPathComponent("/api/auth/me"),
            method: .get,
            headers: headers
        )
        .validate()
        .serializingDecodable(User.self, decoder: dateDecoder)
        .value
    }
    
    /// Logout
    public func logout() async throws {
        if let refreshToken = refreshToken {
            _ = try? await session.request(
                config.apiURL.appendingPathComponent("/api/auth/logout"),
                method: .post,
                parameters: ["refreshToken": refreshToken],
                encoder: JSONParameterEncoder.default,
                headers: headers
            )
            .validate()
            .serializingData()
            .value
        }
        
        accessToken = nil
        self.refreshToken = nil
    }
    
    /// Set tokens manually
    public func setTokens(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    // MARK: - Private
    
    private var headers: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(.contentType("application/json"))
        
        if let apiKey = config.apiKey {
            headers.add(name: "X-API-Key", value: apiKey)
        } else if let accessToken = accessToken {
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
