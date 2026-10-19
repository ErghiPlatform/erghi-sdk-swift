import XCTest
import Alamofire
@testable import ErghiSDK

final class ChatContractTests: XCTestCase {
    typealias Stub = AuthContractTests.Stub

    func makeChat(_ json: [String: Any]) -> ChatResource {
        Stub.seen = []
        Stub.respond = { _ in (200, json) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let config = ErghiConfig(apiURL: URL(string: "https://erghi.test")!)
        let session = Session(configuration: configuration)
        return ChatResource(config: config, session: session, auth: AuthResource(config: config, session: session))
    }

    func testListConversationsSendsPagingQuery() async throws {
        let chat = makeChat(["data": [], "page": 2, "limit": 10, "total": 0, "totalPages": 0])
        let page = try await chat.listConversations(page: 2, limit: 10, status: "active")
        let url = try XCTUnwrap(Stub.seen.first?.request.url)
        XCTAssertEqual(url.path, "/api/conversations")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(Set(items.map { "\($0.name)=\($0.value ?? "")" }), ["page=2", "limit=10", "status=active"])
        XCTAssertEqual(page.page, 2)
    }

    func testCloseAndMarkReadArePosts() async throws {
        let chat = makeChat([:])
        try await chat.closeConversation("c-1")
        try await chat.markAsRead(conversationId: "c-1")
        XCTAssertEqual(Stub.seen.map { "\($0.request.httpMethod ?? "") \($0.request.url?.path ?? "")" }, [
            "POST /api/conversations/c-1/close",
            "POST /api/conversations/c-1/read",
        ])
    }
}
