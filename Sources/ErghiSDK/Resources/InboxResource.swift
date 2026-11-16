import Foundation

// MARK: - Models

/// A workspace conversation label.
public struct ConversationLabel: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let color: String
    public let description: String?
}

public struct ConversationLabelList: Codable, Equatable {
    public let maxLabels: Int
    public let labels: [ConversationLabel]
}

/// A private (internal-only) note on a conversation. Visitors never see notes.
public struct ConversationNote: Codable, Equatable, Identifiable {
    public let id: String
    public let conversationId: String
    public let authorId: String
    public let authorName: String?
    public let content: String
    public let createdAt: Date
    public let updatedAt: Date
    public let canEdit: Bool
    public let canDelete: Bool
}

public struct CannedResponse: Codable, Equatable, Identifiable {
    public let id: String
    public let shortCode: String
    public let content: String
    public let updatedAt: Date
}

public struct CannedResponseList: Codable, Equatable {
    public let maxResponses: Int
    public let responses: [CannedResponse]
}

/// Requires platform PR #256.
public struct UserNotification: Codable, Equatable, Identifiable {
    public let id: String
    public let type: String
    public let conversationId: String?
    public let noteId: String?
    public let actorId: String?
    public let actorName: String?
    public let preview: String?
    public let createdAt: Date
    public let readAt: Date?
}

/// Requires platform PR #256.
public struct MentionableMember: Codable, Equatable {
    public let userId: String
    public let displayName: String?
}

/// A conversation as returned by assignment calls.
public struct AssignedConversation: Codable, Equatable, Identifiable {
    public let id: String
    public let status: String
    public let assignedAgentId: String?
}

// MARK: - Resource

/// Inbox working data: conversation labels, private notes, saved replies and the signed-in
/// teammate's notifications.
///
/// Workspace (admin / server-side) operations: the workspace comes from the API key or access
/// token, never from a parameter. Reading needs `view_conversations`; creating, editing and
/// deleting labels and saved replies needs `manage_inbox_settings`. Notes are written by
/// workspace members: an API key cannot hold the needed permissions (403 on all of these today) and could not write notes anyway: 403 `member_required` when it writes
/// one. Members marked "requires platform PR #256" need that platform release.
public class InboxResource {
    private let http: WorkspaceHTTP

    init(http: WorkspaceHTTP) {
        self.http = http
    }

    private static func s(_ id: String) -> String { WorkspaceHTTP.seg(id) }

    private struct LabelBody: Encodable { let name: String; let color: String?; let description: String? }
    private struct LabelIdsBody: Encodable { let labelIds: [String] }
    private struct NoteBody: Encodable { let content: String; let mentionedUserIds: [String]? }
    private struct CannedBody: Encodable { let shortCode: String; let content: String }
    private struct Count: Decodable { let count: Int }

    // MARK: Labels

    /// The workspace's labels and the per-workspace limit.
    public func listLabels() async throws -> ConversationLabelList {
        try await http.send(ConversationLabelList.self, .get, "/api/v1/conversation-labels")
    }

    /// Needs `manage_inbox_settings`. 409 `label_name_taken` / `label_limit_reached`.
    public func createLabel(name: String, color: String? = nil, description: String? = nil) async throws -> ConversationLabel {
        try await http.send(ConversationLabel.self, .post, "/api/v1/conversation-labels",
                            body: LabelBody(name: name, color: color, description: description))
    }

    /// Needs `manage_inbox_settings`.
    public func updateLabel(id: String, name: String, color: String? = nil, description: String? = nil) async throws -> ConversationLabel {
        try await http.send(ConversationLabel.self, .put, "/api/v1/conversation-labels/\(Self.s(id))",
                            body: LabelBody(name: name, color: color, description: description))
    }

    /// Needs `manage_inbox_settings`. Also removes the label from every conversation.
    public func deleteLabel(id: String) async throws {
        try await http.sendVoid(.delete, "/api/v1/conversation-labels/\(Self.s(id))")
    }

    /// The labels on one conversation.
    public func conversationLabels(conversationId: String) async throws -> [ConversationLabel] {
        try await http.send([ConversationLabel].self, .get, "/api/v1/conversations/\(Self.s(conversationId))/labels")
    }

    /// Replaces the conversation's labels with exactly `labelIds`.
    public func setConversationLabels(conversationId: String, labelIds: [String]) async throws -> [ConversationLabel] {
        try await http.send([ConversationLabel].self, .put, "/api/v1/conversations/\(Self.s(conversationId))/labels",
                            body: LabelIdsBody(labelIds: labelIds))
    }

    /// Adds one label (a no-op if already present). Returns the conversation's labels.
    public func addConversationLabel(conversationId: String, labelId: String) async throws -> [ConversationLabel] {
        try await http.send([ConversationLabel].self, .post,
                            "/api/v1/conversations/\(Self.s(conversationId))/labels/\(Self.s(labelId))")
    }

    /// Removes one label (a no-op if absent). Returns the conversation's labels.
    public func removeConversationLabel(conversationId: String, labelId: String) async throws -> [ConversationLabel] {
        try await http.send([ConversationLabel].self, .delete,
                            "/api/v1/conversations/\(Self.s(conversationId))/labels/\(Self.s(labelId))")
    }

    // MARK: Conversation notes

    public func listNotes(conversationId: String) async throws -> [ConversationNote] {
        try await http.send([ConversationNote].self, .get, "/api/v1/conversations/\(Self.s(conversationId))/notes")
    }

    /// Needs a member token (403 `member_required` for API keys). `mentionedUserIds` requires platform PR #256.
    public func createNote(conversationId: String, content: String, mentionedUserIds: [String]? = nil) async throws -> ConversationNote {
        try await http.send(ConversationNote.self, .post, "/api/v1/conversations/\(Self.s(conversationId))/notes",
                            body: NoteBody(content: content, mentionedUserIds: mentionedUserIds))
    }

    /// Only the author can edit (403 `note_not_author`).
    public func updateNote(conversationId: String, noteId: String, content: String, mentionedUserIds: [String]? = nil) async throws -> ConversationNote {
        try await http.send(ConversationNote.self, .put,
                            "/api/v1/conversations/\(Self.s(conversationId))/notes/\(Self.s(noteId))",
                            body: NoteBody(content: content, mentionedUserIds: mentionedUserIds))
    }

    /// The author or someone with `manage_inbox_settings` can delete.
    public func deleteNote(conversationId: String, noteId: String) async throws {
        try await http.sendVoid(.delete, "/api/v1/conversations/\(Self.s(conversationId))/notes/\(Self.s(noteId))")
    }

    // MARK: Saved replies

    /// Saved replies, optionally filtered by short code prefix or content text.
    public func listCannedResponses(search: String? = nil) async throws -> CannedResponseList {
        var query: [String: String] = [:]
        if let search = search, !search.isEmpty { query["search"] = search }
        return try await http.send(CannedResponseList.self, .get, "/api/v1/canned-responses", query: query)
    }

    /// Needs `manage_inbox_settings`. 409 `canned_response_short_code_taken`.
    public func createCannedResponse(shortCode: String, content: String) async throws -> CannedResponse {
        try await http.send(CannedResponse.self, .post, "/api/v1/canned-responses",
                            body: CannedBody(shortCode: shortCode, content: content))
    }

    /// Needs `manage_inbox_settings`.
    public func updateCannedResponse(id: String, shortCode: String, content: String) async throws -> CannedResponse {
        try await http.send(CannedResponse.self, .put, "/api/v1/canned-responses/\(Self.s(id))",
                            body: CannedBody(shortCode: shortCode, content: content))
    }

    /// Needs `manage_inbox_settings`.
    public func deleteCannedResponse(id: String) async throws {
        try await http.sendVoid(.delete, "/api/v1/canned-responses/\(Self.s(id))")
    }

    // MARK: Assignment, notifications, mentions (require platform PR #256)

    /// Returns the conversation to the queue. Requires platform PR #256. 409 for resolved or closed conversations.
    public func unassignConversation(conversationId: String) async throws -> AssignedConversation {
        try await http.send(AssignedConversation.self, .post, "/api/conversations/\(Self.s(conversationId))/unassign")
    }

    /// The signed-in teammate's notifications, newest first. Requires platform PR #256.
    /// Notifications belong to a member, so an API key gets an empty list.
    public func listNotifications(unreadOnly: Bool = false, limit: Int? = nil) async throws -> [UserNotification] {
        var query: [String: String] = [:]
        if unreadOnly { query["unreadOnly"] = "true" }
        if let limit = limit { query["limit"] = String(limit) }
        return try await http.send([UserNotification].self, .get, "/api/v1/notifications", query: query)
    }

    /// Requires platform PR #256.
    public func unreadNotificationCount() async throws -> Int {
        try await http.send(Count.self, .get, "/api/v1/notifications/unread-count").count
    }

    /// Requires platform PR #256.
    public func markNotificationRead(id: String) async throws {
        try await http.sendVoid(.post, "/api/v1/notifications/\(Self.s(id))/read")
    }

    /// Requires platform PR #256.
    public func markAllNotificationsRead() async throws {
        try await http.sendVoid(.post, "/api/v1/notifications/read-all")
    }

    /// Teammates who can be @mentioned in a note. Requires platform PR #256.
    public func mentionableMembers() async throws -> [MentionableMember] {
        try await http.send([MentionableMember].self, .get, "/api/v1/team/mentionable")
    }
}
