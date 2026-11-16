import Foundation

/// Requires platform PR #256.
public struct ContactSummary: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let email: String?
    public let phone: String?
    public let externalId: String?
    public let firstSeenAt: Date
    public let lastSeenAt: Date
    public let blocked: Bool
    public let conversationCount: Int
}

/// Requires platform PR #256.
public struct ContactPage: Codable, Equatable {
    public let items: [ContactSummary]
    public let total: Int
    public let page: Int
    public let pageSize: Int
}

public struct ContactConversation: Codable, Equatable, Identifiable {
    public let id: String
    public let channel: String
    public let status: String
    public let startedAt: Date
    public let closedAt: Date?
    public let assignedAgentId: String?
}

/// Requires platform PR #256.
public struct ContactDetail: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let email: String?
    public let phone: String?
    public let externalId: String?
    public let locale: String?
    public let firstSeenAt: Date
    public let lastSeenAt: Date
    public let blocked: Bool
    public let blockedAt: Date?
    public let conversations: [ContactConversation]
}

/// A private note on a contact. Requires platform PR #256.
public struct ContactNote: Codable, Equatable, Identifiable {
    public let id: String
    public let contactId: String
    public let authorId: String
    public let authorName: String?
    public let content: String
    public let createdAt: Date
    public let updatedAt: Date
    public let canEdit: Bool
    public let canDelete: Bool
}

public struct ContactEraseResult: Codable, Equatable {
    public let conversationsDeleted: Int
    public let messagesDeleted: Int
}

/// Contacts: the people who have chatted with the workspace. Requires platform PR #256.
///
/// Workspace (admin / server-side) operations: the workspace comes from the API key or access
/// token. Reading needs `view_conversations`; update, block, unblock and erase need
/// `manage_contacts`. An API key can read contact notes but cannot author them.
public class ContactsResource {
    private let http: WorkspaceHTTP

    init(http: WorkspaceHTTP) {
        self.http = http
    }

    private static func s(_ id: String) -> String { WorkspaceHTTP.seg(id) }

    private struct UpdateBody: Encodable { let name: String?; let email: String?; let phone: String? }
    private struct NoteBody: Encodable { let content: String }

    /// `search` matches name, email, phone or external id. `pageSize` is capped at 100 by the server.
    public func list(search: String? = nil, blocked: Bool? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> ContactPage {
        var query: [String: String] = [:]
        if let search = search, !search.isEmpty { query["search"] = search }
        if let blocked = blocked { query["blocked"] = blocked ? "true" : "false" }
        if let page = page { query["page"] = String(page) }
        if let pageSize = pageSize { query["pageSize"] = String(pageSize) }
        return try await http.send(ContactPage.self, .get, "/api/v1/contacts", query: query)
    }

    public func get(id: String) async throws -> ContactDetail {
        try await http.send(ContactDetail.self, .get, "/api/v1/contacts/\(Self.s(id))")
    }

    /// Needs `manage_contacts`. A nil field is unchanged; an empty string clears it.
    public func update(id: String, name: String? = nil, email: String? = nil, phone: String? = nil) async throws -> ContactDetail {
        try await http.send(ContactDetail.self, .patch, "/api/v1/contacts/\(Self.s(id))",
                            body: UpdateBody(name: name, email: email, phone: phone))
    }

    /// Needs `manage_contacts`.
    public func block(id: String) async throws {
        try await http.sendVoid(.post, "/api/v1/contacts/\(Self.s(id))/block")
    }

    /// Needs `manage_contacts`.
    public func unblock(id: String) async throws {
        try await http.sendVoid(.post, "/api/v1/contacts/\(Self.s(id))/unblock")
    }

    /// Needs `manage_contacts`. IRREVERSIBLY deletes the contact and all of their conversations
    /// and messages (GDPR erasure); the server records it in the security audit log.
    public func erase(id: String) async throws -> ContactEraseResult {
        try await http.send(ContactEraseResult.self, .delete, "/api/v1/contacts/\(Self.s(id))")
    }

    public func listNotes(contactId: String) async throws -> [ContactNote] {
        try await http.send([ContactNote].self, .get, "/api/v1/contacts/\(Self.s(contactId))/notes")
    }

    /// Needs a member token (403 `member_required` for API keys).
    public func createNote(contactId: String, content: String) async throws -> ContactNote {
        try await http.send(ContactNote.self, .post, "/api/v1/contacts/\(Self.s(contactId))/notes", body: NoteBody(content: content))
    }

    /// Only the author can edit (403 `note_not_author`).
    public func updateNote(contactId: String, noteId: String, content: String) async throws -> ContactNote {
        try await http.send(ContactNote.self, .put, "/api/v1/contacts/\(Self.s(contactId))/notes/\(Self.s(noteId))",
                            body: NoteBody(content: content))
    }

    /// The author or someone with `manage_contacts` can delete.
    public func deleteNote(contactId: String, noteId: String) async throws {
        try await http.sendVoid(.delete, "/api/v1/contacts/\(Self.s(contactId))/notes/\(Self.s(noteId))")
    }
}
