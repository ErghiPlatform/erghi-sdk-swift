import Foundation
import Alamofire

/// Authentication resource for Erghi SDK
public class AuthResource {
    private let config: ErghiConfig
    private let session: Session
    
    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    
    init(config: ErghiConfig, session: Session) {
        self.config = config
        self.session = session
    }
    
    /// Register a new user. `/api/auth/*` is the platform's GoTrue auth server
    /// behind the gateway, so bodies are GoTrue's snake_case shapes. Tokens are
    /// empty while the platform waits for email confirmation (see `verifyEmail`).
    public func register(_ request: RegisterRequest) async throws -> AuthResponse {
        var body: [String: Any] = [
            "email": request.email,
            "password": request.password,
            "data": ["first_name": request.firstName, "last_name": request.lastName],
        ]
        if let phone = request.phoneNumber { body["phone"] = phone }
        let data = try await send(.post, "/api/auth/register", body: body)
        return store(try GoTrue.authResponse(from: data))
    }

    /// Login with email and password
    public func login(_ request: LoginRequest) async throws -> AuthResponse {
        let data = try await send(.post, "/api/auth/login",
                                  body: ["email": request.email, "password": request.password])
        return store(try GoTrue.authResponse(from: data))
    }

    /// Refresh access token
    public func refresh() async throws -> AuthResponse {
        guard let refreshToken = refreshToken else {
            throw ErghiError.authenticationFailed("No refresh token available")
        }
        let data = try await send(.post, "/api/auth/token",
                                  query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                  body: ["refresh_token": refreshToken])
        return store(try GoTrue.authResponse(from: data))
    }

    /// Get current user
    public func me() async throws -> User {
        let data = try await send(.get, "/api/auth/user")
        return try GoTrue.user(from: data)
    }

    /// Logout
    public func logout() async throws {
        if accessToken != nil {
            _ = try? await send(.post, "/api/auth/logout")
        }
        accessToken = nil
        self.refreshToken = nil
    }

    /// Confirm a signup with the token from the confirmation email link.
    public func verifyEmail(token: String) async throws {
        let data = try await send(.post, "/api/auth/verify",
                                  body: ["type": "signup", "token_hash": token])
        _ = store(try GoTrue.authResponse(from: data))
    }

    /// Send a password reset email.
    public func forgotPassword(email: String) async throws {
        _ = try await send(.post, "/api/auth/recover", body: ["email": email])
    }

    /// Set a new password using the token from the reset email link: the token is
    /// exchanged for a recovery session, which then updates the password.
    public func resetPassword(token: String, newPassword: String) async throws {
        let data = try await send(.post, "/api/auth/verify",
                                  body: ["type": "recovery", "token_hash": token])
        let session = try? JSONDecoder().decode(GoTrue.Session.self, from: data)
        guard let recoveryToken = session?.access_token, !recoveryToken.isEmpty else {
            throw ErghiError.authenticationFailed("Password reset token was not accepted")
        }
        _ = try await send(.put, "/api/auth/user", body: ["password": newPassword],
                           bearer: recoveryToken)
    }

    private func store(_ auth: AuthResponse) -> AuthResponse {
        if !auth.accessToken.isEmpty {
            accessToken = auth.accessToken
            refreshToken = auth.refreshToken
        }
        return auth
    }

    private func send(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        bearer: String? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: config.apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = try URLRequest(url: components.url!, method: method, headers: headers)
        if let bearer = bearer {
            request.headers.remove(name: "X-API-Key")
            request.headers.add(.authorization(bearerToken: bearer))
        }
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let response = await session.request(request).serializingData(emptyResponseCodes: [200, 204, 205]).response
        let data = response.data ?? Data()
        guard let status = response.response?.statusCode else {
            throw ErghiError.networkError(response.error?.localizedDescription ?? "No response")
        }
        if (200..<300).contains(status) { return data }

        // GoTrue reports errors as `msg` / `error_description`.
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = ["msg", "error_description", "message", "error"]
            .compactMap { json[$0] as? String }.first ?? "HTTP \(status)"
        switch status {
        case 400, 422: throw ErghiError.validationError(message)
        case 404: throw ErghiError.notFound(message)
        default: throw ErghiError.authenticationFailed(message)
        }
    }

    /// Set tokens manually
    public func setTokens(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    internal func storeM2MToken(_ token: String) {
        self.accessToken = token
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
    
}

/// Raw GoTrue shapes (snake_case), mapped onto the SDK's public models.
enum GoTrue {
    struct Session: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Int?
        let user: UserObject?
    }

    struct UserObject: Decodable {
        let id: String
        let email: String?
        let phone: String?
        let email_confirmed_at: String?
        let created_at: String?
        let updated_at: String?
        let user_metadata: [String: JSONValue]?
        let app_metadata: [String: JSONValue]?
    }

    enum JSONValue: Decodable {
        case string(String)
        case other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                self = .other
            }
        }

        var string: String? {
            if case .string(let value) = self { return value }
            return nil
        }
    }

    static func user(from data: Data) throws -> User {
        map(try JSONDecoder().decode(UserObject.self, from: data))
    }

    /// A session, or the bare user `/signup` returns while email confirmation is
    /// pending (tokens are then empty).
    static func authResponse(from data: Data) throws -> AuthResponse {
        let session = try JSONDecoder().decode(Session.self, from: data)
        let user = try session.user ?? JSONDecoder().decode(UserObject.self, from: data)
        return AuthResponse(
            accessToken: session.access_token ?? "",
            refreshToken: session.refresh_token ?? "",
            user: map(user),
            expiresIn: session.expires_in ?? 0
        )
    }

    static func map(_ user: UserObject) -> User {
        let created = date(user.created_at) ?? Date(timeIntervalSince1970: 0)
        return User(
            id: user.id,
            email: user.email ?? "",
            firstName: user.user_metadata?["first_name"]?.string ?? "",
            lastName: user.user_metadata?["last_name"]?.string ?? "",
            phoneNumber: (user.phone?.isEmpty ?? true) ? nil : user.phone,
            avatarUrl: user.user_metadata?["avatar_url"]?.string,
            role: user.app_metadata?["role"]?.string.flatMap(UserRole.init(rawValue:)) ?? .member,
            emailVerified: user.email_confirmed_at != nil,
            createdAt: created,
            updatedAt: date(user.updated_at) ?? created
        )
    }

    private static func date(_ value: String?) -> Date? {
        guard let value = value else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
