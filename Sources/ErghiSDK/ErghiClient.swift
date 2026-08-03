import Foundation
import Alamofire
import Starscream
import Combine

/// Main Erghi SDK Client
public class ErghiClient {
    /// ASP.NET Core SignalR's JSON Hub Protocol terminates every frame with this character.
    private static let recordSeparator = "\u{1e}"

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

    private var handshakeCompleted = false
    private var handshakeContinuation: CheckedContinuation<Void, Error>?
    private var pendingInvocations: [String: CheckedContinuation<Any?, Error>] = [:]
    private var keepaliveTask: Task<Void, Never>?

    public private(set) var visitorId: String?

    /// Stream of real-time messages
    public var messagePublisher: AnyPublisher<Message, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    /// Check if the real-time hub is connected
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

    /// Connect to the real-time hub for real-time updates.
    ///
    /// Was a raw Starscream `WebSocket` speaking a hand-rolled {type, conversationId} envelope
    /// directly at /hubs/chat -- that never completes the SignalR negotiate/handshake a real
    /// ASP.NET Core SignalR hub requires (a POST to /negotiate for a connection token, then a
    /// JSON handshake record before any invocation frames are accepted), so it could not
    /// actually exchange messages with the real backend. This implements that protocol
    /// directly on top of the same Starscream connection, since no official/maintained
    /// SignalR client exists for Swift. Also fixes a standing bug where the auth headers this
    /// method built were never actually attached to the connection (Starscream/WebSocket
    /// upgrade requests don't reliably carry custom headers across platforms the way plain
    /// HTTP requests do) -- auth now travels the way the real hub actually expects it (an
    /// `access_token` query parameter, the same mechanism browsers use since they can't set
    /// custom headers on a WebSocket upgrade either).
    public func connectWebSocket() async throws {
        guard !isConnected else { return }

        let token = try await negotiate()

        guard var components = URLComponents(
            url: config.websocketURL.appendingPathComponent("/hubs/chat"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ErghiError.webSocketError("Invalid hub URL")
        }
        let accessToken = config.apiKey ?? auth.accessToken ?? ""
        components.queryItems = [
            URLQueryItem(name: "id", value: token),
            URLQueryItem(name: "access_token", value: accessToken),
        ]
        guard let url = components.url else {
            throw ErghiError.webSocketError("Invalid hub URL")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.handshakeCompleted = false
            self.handshakeContinuation = continuation
            let webSocket = WebSocket(request: URLRequest(url: url))
            webSocket.delegate = self
            self.webSocket = webSocket
            webSocket.connect()
        }

        startKeepalive()
    }

    private struct NegotiateResponse: Decodable {
        let connectionToken: String?
        let connectionId: String?
        let url: String?
    }

    /// POST /hubs/chat/negotiate to obtain the connection token the WebSocket URL needs.
    private func negotiate() async throws -> String {
        let response = try await session.request(
            config.apiURL.appendingPathComponent("/hubs/chat/negotiate"),
            method: .post,
            parameters: ["negotiateVersion": 1],
            encoding: URLEncoding(destination: .queryString)
        )
        .validate()
        .serializingDecodable(NegotiateResponse.self)
        .value

        if response.url != nil {
            // Azure SignalR-style redirect to a different endpoint -- not used by this
            // platform's self-hosted deployment, but fail clearly instead of silently
            // connecting to the wrong place if it ever is.
            throw ErghiError.webSocketError("Hub negotiate returned a redirect target; not supported")
        }
        guard let token = response.connectionToken ?? response.connectionId else {
            throw ErghiError.webSocketError("Hub negotiate response had no connection token")
        }
        return token
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self = self, self.isConnected else { continue }
                self.webSocket?.write(string: "{\"type\":6}" + Self.recordSeparator)
            }
        }
    }

    /// Disconnect from the hub.
    public func disconnectWebSocket() {
        keepaliveTask?.cancel()
        keepaliveTask = nil

        for (_, continuation) in pendingInvocations {
            continuation.resume(throwing: ErghiError.webSocketError("Hub disconnected"))
        }
        pendingInvocations.removeAll()

        webSocket?.disconnect()
        webSocket = nil
        isConnected = false
    }

    /// Invoke a real hub method (e.g. "SendTyping", "JoinConversation", "MarkAsRead").
    ///
    /// When `waitForResult` is true (the default), waits for the server's Completion message
    /// and throws `ErghiError.hubException` if the server rejected the call -- notably
    /// including ConversationOwnershipHubFilter denying access to a conversation outside the
    /// caller's own workspace, which the previous transport could never have surfaced since it
    /// never spoke to a real hub at all.
    @discardableResult
    public func invoke(_ method: String, arguments: [Any], waitForResult: Bool = true) async throws -> Any? {
        guard isConnected, let webSocket = webSocket else {
            throw ErghiError.webSocketError("Hub is not connected")
        }

        var message: [String: Any] = ["type": 1, "target": method, "arguments": arguments]
        var invocationId: String?
        if waitForResult {
            let id = UUID().uuidString
            invocationId = id
            message["invocationId"] = id
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ErghiError.webSocketError("Failed to encode hub invocation")
        }

        guard let invocationId = invocationId else {
            webSocket.write(string: jsonString + Self.recordSeparator)
            return nil
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            self.pendingInvocations[invocationId] = continuation
            webSocket.write(string: jsonString + Self.recordSeparator)
        }
    }

    /// Send typing indicator. Fire-and-forget, matching this method's previous behavior.
    public func sendTyping(conversationId: String) {
        guard isConnected else { return }
        Task {
            _ = try? await invoke("SendTyping", arguments: [conversationId], waitForResult: false)
        }
    }

    /// Join a conversation's real-time group -- required before UserTyping/MessageRead events
    /// for that conversation are delivered to this connection. Throws
    /// `ErghiError.hubException` if the conversation isn't in the caller's own workspace.
    public func joinConversation(_ conversationId: String) async throws {
        guard isConnected else { return }
        _ = try await invoke("JoinConversation", arguments: [conversationId])
    }

    /// Leave a conversation's real-time group.
    public func leaveConversation(_ conversationId: String) async throws {
        guard isConnected else { return }
        _ = try await invoke("LeaveConversation", arguments: [conversationId], waitForResult: false)
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
            if config.debug {
                print("Hub transport connected, sending handshake")
            }
            webSocket?.write(string: "{\"protocol\":\"json\",\"version\":1}" + Self.recordSeparator)

        case .disconnected(let reason, let code):
            isConnected = false
            failPendingInvocations(ErghiError.webSocketError("Hub disconnected: \(reason) (code: \(code))"))
            if config.debug {
                print("Hub disconnected: \(reason) (code: \(code))")
            }

        case .text(let string):
            handleIncomingText(string)

        case .error(let error):
            isConnected = false
            let message = error?.localizedDescription ?? "unknown error"
            failPendingInvocations(ErghiError.webSocketError(message))
            if let handshakeContinuation = handshakeContinuation {
                self.handshakeContinuation = nil
                handshakeContinuation.resume(throwing: ErghiError.webSocketError(message))
            }
            if config.debug {
                print("Hub error: \(message)")
            }

        default:
            break
        }
    }

    private func failPendingInvocations(_ error: Error) {
        for (_, continuation) in pendingInvocations {
            continuation.resume(throwing: error)
        }
        pendingInvocations.removeAll()
    }

    private func handleIncomingText(_ text: String) {
        let records = text.components(separatedBy: Self.recordSeparator).filter { !$0.isEmpty }
        for record in records {
            if !handshakeCompleted {
                handshakeCompleted = true
                handleHandshakeResponse(record)
            } else {
                handleHubRecord(record)
            }
        }
    }

    private func handleHandshakeResponse(_ record: String) {
        guard let data = record.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            resumeHandshake(throwing: ErghiError.webSocketError("Malformed handshake response"))
            return
        }

        if let error = json["error"] as? String {
            resumeHandshake(throwing: ErghiError.webSocketError("Hub handshake failed: \(error)"))
            return
        }

        isConnected = true
        resumeHandshake(throwing: nil)
    }

    private func resumeHandshake(throwing error: Error?) {
        guard let continuation = handshakeContinuation else { return }
        handshakeContinuation = nil
        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func handleHubRecord(_ record: String) {
        guard let data = record.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? Int else {
            return
        }

        switch type {
        case 1:
            // Invocation from the server -- a hub broadcast (MessageReceived, UserTyping, ...).
            guard let target = json["target"] as? String,
                  let arguments = json["arguments"] as? [Any] else {
                return
            }
            if target == "MessageReceived", let first = arguments.first as? [String: Any] {
                handleMessageReceived(first)
            }

        case 3:
            // Completion -- the response to one of our own invoke() calls.
            guard let invocationId = json["invocationId"] as? String,
                  let continuation = pendingInvocations.removeValue(forKey: invocationId) else {
                return
            }
            if let error = json["error"] as? String {
                continuation.resume(throwing: ErghiError.hubException(error))
            } else {
                continuation.resume(returning: json["result"])
            }

        case 7:
            // Server-initiated close.
            isConnected = false
            if config.debug, let error = json["error"] as? String {
                print("Hub sent close: \(error)")
            }

        default:
            // Type 6 (ping) needs no application-level response beyond our own keepalive task.
            // Types 2/4/5 (streaming) are not used by ChatHub/VisitorChatHub.
            break
        }
    }

    private func handleMessageReceived(_ payload: [String: Any]) {
        guard let messageJson = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let message = try? decoder.decode(Message.self, from: messageJson) {
            messageSubject.send(message)
        }
    }
}
