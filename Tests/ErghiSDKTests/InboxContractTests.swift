import XCTest
import Alamofire
@testable import ErghiSDK

final class InboxContractTests: XCTestCase {
    typealias Stub = AuthContractTests.Stub

    static let label: [String: Any] = ["id": "l-1", "name": "VIP", "color": "#ff0000", "description": NSNull()]
    static let note: [String: Any] = [
        "id": "n-1", "conversationId": "c-1", "authorId": "u-1", "authorName": "Sam", "content": "hi",
        "createdAt": "2026-11-10T10:00:00Z", "updatedAt": "2026-11-10T10:00:00Z", "canEdit": true, "canDelete": true,
    ]

    func make(json: [String: Any] = [:], array: Any? = nil, status: Int = 200) -> (InboxResource, ContactsResource) {
        Stub.seen = []
        if let array = array {
            Stub.rawBody = try! JSONSerialization.data(withJSONObject: array)
        } else {
            Stub.rawBody = status == 204 ? Data() : nil
        }
        Stub.respond = { _ in (status, json) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let config = ErghiConfig(apiURL: URL(string: "https://erghi.test")!, apiKey: "key-1")
        let session = Session(configuration: configuration)
        let http = WorkspaceHTTP(config: config, session: session, auth: AuthResource(config: config, session: session))
        return (InboxResource(http: http), ContactsResource(http: http))
    }

    override func tearDown() {
        Stub.rawBody = nil
        super.tearDown()
    }

    private func query(_ index: Int = 0) throws -> [String: String] {
        let url = try XCTUnwrap(Stub.seen[index].request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testLabelCrudUsesRightVerbsAndPaths() async throws {
        var (inbox, _) = make(json: ["maxLabels": 50, "labels": [Self.label]])
        let list = try await inbox.listLabels()
        XCTAssertEqual(list.maxLabels, 50)
        XCTAssertEqual(list.labels[0].name, "VIP")
        XCTAssertEqual(Stub.seen[0].request.value(forHTTPHeaderField: "X-API-Key"), "key-1")

        (inbox, _) = make(json: Self.label)
        _ = try await inbox.createLabel(name: "VIP", color: "#ff0000")
        XCTAssertEqual(Stub.seen[0].request.httpMethod, "POST")
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/v1/conversation-labels")
        XCTAssertEqual(Stub.seen[0].body["name"] as? String, "VIP")
        XCTAssertNil(Stub.seen[0].body["description"])
        _ = try await inbox.updateLabel(id: "l-1", name: "Vip")
        XCTAssertEqual(Stub.seen[1].request.httpMethod, "PUT")

        (inbox, _) = make(status: 204)
        try await inbox.deleteLabel(id: "l-1")
        XCTAssertEqual(Stub.seen[0].request.httpMethod, "DELETE")
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/v1/conversation-labels/l-1")
    }

    func testConversationLabelSetAddRemove() async throws {
        let (inbox, _) = make(array: [Self.label])
        _ = try await inbox.setConversationLabels(conversationId: "c-1", labelIds: ["l-1", "l-2"])
        XCTAssertEqual(Stub.seen[0].request.httpMethod, "PUT")
        XCTAssertEqual(Stub.seen[0].body["labelIds"] as? [String], ["l-1", "l-2"])
        let after = try await inbox.addConversationLabel(conversationId: "c-1", labelId: "l-1")
        XCTAssertEqual(after[0].id, "l-1")
        XCTAssertEqual(Stub.seen[1].request.url?.path, "/api/v1/conversations/c-1/labels/l-1")
        _ = try await inbox.removeConversationLabel(conversationId: "c-1", labelId: "l-1")
        XCTAssertEqual(Stub.seen[2].request.httpMethod, "DELETE")
    }

    func testNotesSendMentionsOnlyWhenGiven() async throws {
        let (inbox, _) = make(json: Self.note)
        let note = try await inbox.createNote(conversationId: "c-1", content: "hi")
        XCTAssertEqual(note.authorName, "Sam")
        XCTAssertEqual(Stub.seen[0].body["content"] as? String, "hi")
        XCTAssertNil(Stub.seen[0].body["mentionedUserIds"])
        _ = try await inbox.createNote(conversationId: "c-1", content: "hi @a", mentionedUserIds: ["u-2"])
        XCTAssertEqual(Stub.seen[1].body["mentionedUserIds"] as? [String], ["u-2"])
        _ = try await inbox.updateNote(conversationId: "c-1", noteId: "n-1", content: "x")
        XCTAssertEqual(Stub.seen[2].request.url?.path, "/api/v1/conversations/c-1/notes/n-1")
    }

    func testApiKeyNoteWriteForbiddenThrows() async throws {
        let (inbox, _) = make(json: ["error": "member_required"], status: 403)
        do {
            _ = try await inbox.createNote(conversationId: "c-1", content: "hi")
            XCTFail("expected a 403")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testCannedResponsesSearchOnlyWhenSet() async throws {
        let (inbox, _) = make(json: [
            "maxResponses": 100,
            "responses": [["id": "r-1", "shortCode": "hi", "content": "Hello", "updatedAt": "2026-11-10T10:00:00Z"]],
        ])
        let list = try await inbox.listCannedResponses()
        XCTAssertEqual(list.responses[0].shortCode, "hi")
        XCTAssertEqual(try query(0), [:])
        _ = try await inbox.listCannedResponses(search: "hel")
        XCTAssertEqual(try query(1), ["search": "hel"])
    }

    func testNotificationsCountAndMentionable() async throws {
        var (inbox, _) = make(array: [[
            "id": "x-1", "type": "mention", "conversationId": "c-1", "noteId": "n-1", "actorId": "u-2",
            "actorName": "Lee", "preview": "hi", "createdAt": "2026-11-10T10:00:00Z", "readAt": NSNull(),
        ]])
        let items = try await inbox.listNotifications(unreadOnly: true, limit: 10)
        XCTAssertEqual(items[0].actorName, "Lee")
        XCTAssertNil(items[0].readAt)
        XCTAssertEqual(try query(), ["unreadOnly": "true", "limit": "10"])

        (inbox, _) = make(json: ["count": 3])
        let count = try await inbox.unreadNotificationCount()
        XCTAssertEqual(count, 3)

        (inbox, _) = make(array: [["userId": "u-2", "displayName": "Lee"]])
        let members = try await inbox.mentionableMembers()
        XCTAssertEqual(members[0].userId, "u-2")

        (inbox, _) = make(status: 204)
        try await inbox.markNotificationRead(id: "x-1")
        try await inbox.markAllNotificationsRead()
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/v1/notifications/x-1/read")
        XCTAssertEqual(Stub.seen[1].request.url?.path, "/api/v1/notifications/read-all")
    }

    func testUnassignPostsToLegacyConversationPath() async throws {
        let (inbox, _) = make(json: ["id": "c-1", "status": "Open", "assignedAgentId": NSNull()])
        let conversation = try await inbox.unassignConversation(conversationId: "c-1")
        XCTAssertNil(conversation.assignedAgentId)
        XCTAssertEqual(Stub.seen[0].request.httpMethod, "POST")
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/conversations/c-1/unassign")
    }

    func testContactsListGetUpdateBlockErase() async throws {
        var (_, contacts) = make(json: [
            "items": [[
                "id": "k-1", "name": "Ann", "email": NSNull(), "phone": NSNull(), "externalId": "x",
                "firstSeenAt": "2026-11-01T10:00:00Z", "lastSeenAt": "2026-11-02T10:00:00Z",
                "blocked": false, "conversationCount": 2,
            ]],
            "total": 1, "page": 2, "pageSize": 25,
        ])
        let page = try await contacts.list(search: "ann", blocked: false, page: 2)
        XCTAssertEqual(page.items[0].conversationCount, 2)
        XCTAssertEqual(try query(), ["search": "ann", "blocked": "false", "page": "2"])

        (_, contacts) = make(json: [
            "id": "k-1", "name": "Ann", "email": NSNull(), "phone": NSNull(), "externalId": NSNull(),
            "locale": "ar", "firstSeenAt": "2026-11-01T10:00:00Z", "lastSeenAt": "2026-11-02T10:00:00Z",
            "blocked": false, "blockedAt": NSNull(),
            "conversations": [[
                "id": "c-1", "channel": "widget", "status": "open", "startedAt": "2026-11-01T10:00:00Z",
                "closedAt": NSNull(), "assignedAgentId": NSNull(),
            ]],
        ])
        let detail = try await contacts.get(id: "k-1")
        XCTAssertEqual(detail.locale, "ar")
        XCTAssertEqual(detail.conversations[0].status, "open")
        _ = try await contacts.update(id: "k-1", email: "")
        XCTAssertEqual(Stub.seen[1].request.httpMethod, "PATCH")
        XCTAssertEqual(Stub.seen[1].body["email"] as? String, "")
        XCTAssertNil(Stub.seen[1].body["name"])

        (_, contacts) = make(status: 204)
        try await contacts.block(id: "k-1")
        try await contacts.unblock(id: "k-1")
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/v1/contacts/k-1/block")
        XCTAssertEqual(Stub.seen[1].request.url?.path, "/api/v1/contacts/k-1/unblock")

        (_, contacts) = make(json: ["conversationsDeleted": 2, "messagesDeleted": 9])
        let erased = try await contacts.erase(id: "k-1")
        XCTAssertEqual(erased.messagesDeleted, 9)
        XCTAssertEqual(Stub.seen[0].request.httpMethod, "DELETE")
    }

    func testContactNotes() async throws {
        let (_, contacts) = make(json: [
            "id": "n-1", "contactId": "k-1", "authorId": "u-1", "authorName": NSNull(), "content": "vip",
            "createdAt": "2026-11-10T10:00:00Z", "updatedAt": "2026-11-10T10:00:00Z",
            "canEdit": true, "canDelete": false,
        ])
        let note = try await contacts.createNote(contactId: "k-1", content: "vip")
        XCTAssertEqual(note.contactId, "k-1")
        XCTAssertEqual(Stub.seen[0].body["content"] as? String, "vip")
        _ = try await contacts.updateNote(contactId: "k-1", noteId: "n-1", content: "x")
        XCTAssertEqual(Stub.seen[1].request.url?.path, "/api/v1/contacts/k-1/notes/n-1")
    }
}
