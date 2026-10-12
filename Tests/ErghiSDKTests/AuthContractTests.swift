import XCTest
import Alamofire
@testable import ErghiSDK

/// Pins the wire contract: `/api/auth/*` is GoTrue behind the gateway, so paths
/// and bodies are GoTrue's (snake_case).
final class AuthContractTests: XCTestCase {
    final class Stub: URLProtocol {
        static var respond: (URLRequest) -> (Int, [String: Any]) = { _ in (200, [:]) }
        static var seen: [(request: URLRequest, body: [String: Any])] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            var bodyData = request.httpBody
            if bodyData == nil, let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                stream.close()
                bodyData = data
            }
            let body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            Stub.seen.append((request, body))
            let (status, json) = Stub.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    static let user: [String: Any] = [
        "id": "u-1", "email": "qa@example.com", "role": "authenticated",
        "email_confirmed_at": "2026-10-01T00:00:00Z", "created_at": "2026-10-01T00:00:00Z",
        "user_metadata": ["first_name": "Q", "last_name": "A"],
    ]
    static let session: [String: Any] = [
        "access_token": "at-1", "refresh_token": "rt-1", "expires_in": 3600,
        "token_type": "bearer", "user": user,
    ]

    func makeAuth(_ respond: @escaping (URLRequest) -> (Int, [String: Any])) -> AuthResource {
        Stub.seen = []
        Stub.respond = respond
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let config = ErghiConfig(apiURL: URL(string: "https://erghi.test")!)
        return AuthResource(config: config, session: Session(configuration: configuration))
    }

    func testLoginMapsSnakeCaseSession() async throws {
        let auth = makeAuth { _ in (200, Self.session) }
        let result = try await auth.login(LoginRequest(email: "qa@example.com", password: "pw"))
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/auth/login")
        XCTAssertEqual(Stub.seen[0].body as? [String: String], ["email": "qa@example.com", "password": "pw"])
        XCTAssertEqual(result.accessToken, "at-1")
        XCTAssertEqual(result.user.firstName, "Q")
        XCTAssertTrue(result.user.emailVerified)
        XCTAssertEqual(auth.accessToken, "at-1")
    }

    func testRefreshUsesTokenGrant() async throws {
        let auth = makeAuth { _ in (200, Self.session) }
        auth.setTokens(accessToken: nil, refreshToken: "rt-0")
        _ = try await auth.refresh()
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/auth/token")
        XCTAssertEqual(Stub.seen[0].request.url?.query, "grant_type=refresh_token")
        XCTAssertEqual(Stub.seen[0].body["refresh_token"] as? String, "rt-0")
    }

    func testRegisterPendingConfirmationHasNoTokens() async throws {
        var pending = Self.user
        pending["email_confirmed_at"] = NSNull()
        let auth = makeAuth { _ in (200, pending) }
        let result = try await auth.register(
            RegisterRequest(email: "qa@example.com", password: "pw", firstName: "Q", lastName: "A"))
        XCTAssertEqual((Stub.seen[0].body["data"] as? [String: String])?["first_name"], "Q")
        XCTAssertEqual(result.accessToken, "")
        XCTAssertFalse(result.user.emailVerified)
        XCTAssertNil(auth.accessToken)
    }

    func testMeAndForgotPasswordPaths() async throws {
        let auth = makeAuth { request in (200, request.httpMethod == "GET" ? Self.user : [:]) }
        let me = try await auth.me()
        try await auth.forgotPassword(email: "qa@example.com")
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/auth/user")
        XCTAssertEqual(me.id, "u-1")
        XCTAssertEqual(Stub.seen[1].request.url?.path, "/api/auth/recover")
    }

    func testResetPasswordUsesRecoverySession() async throws {
        let auth = makeAuth { request in (200, request.httpMethod == "POST" ? ["access_token": "recovery-at"] : [:]) }
        try await auth.resetPassword(token: "hash-1", newPassword: "new-pw")
        XCTAssertEqual(Stub.seen[0].body as? [String: String], ["type": "recovery", "token_hash": "hash-1"])
        XCTAssertEqual(Stub.seen[1].request.httpMethod, "PUT")
        XCTAssertEqual(Stub.seen[1].request.url?.path, "/api/auth/user")
        XCTAssertEqual(Stub.seen[1].request.value(forHTTPHeaderField: "Authorization"), "Bearer recovery-at")
    }

    func testGoTrueErrorTextIsSurfaced() async {
        let auth = makeAuth { _ in (400, ["code": 400, "msg": "Invalid login credentials"]) }
        do {
            _ = try await auth.login(LoginRequest(email: "qa@example.com", password: "x"))
            XCTFail("expected an error")
        } catch ErghiError.validationError(let message) {
            XCTAssertEqual(message, "Invalid login credentials")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
