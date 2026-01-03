import Foundation

// MARK: - User

public struct User: Codable, Equatable, Identifiable {
    public let id: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let phoneNumber: String?
    public let avatarUrl: String?
    public let role: UserRole
    public let emailVerified: Bool
    public let createdAt: Date
    public let updatedAt: Date
    
    public var fullName: String {
        "\(firstName) \(lastName)"
    }
}

public enum UserRole: String, Codable {
    case admin
    case member
    case viewer
}

// MARK: - Auth

public struct AuthResponse: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let user: User
    public let expiresIn: Int
}

public struct RegisterRequest: Codable {
    public let email: String
    public let password: String
    public let firstName: String
    public let lastName: String
    public let phoneNumber: String?
    
    public init(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        phoneNumber: String? = nil
    ) {
        self.email = email
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
    }
}

public struct LoginRequest: Codable {
    public let email: String
    public let password: String
    
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct RefreshRequest: Codable {
    public let refreshToken: String
    
    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

// MARK: - Conversation

public struct Conversation: Codable, Equatable, Identifiable {
    public let id: String
    public let widgetId: String
    public let visitorId: String?
    public let assignedTo: String?
    public let status: ConversationStatus
    public let metadata: [String: AnyCodable]?
    public let createdAt: Date
    public let updatedAt: Date
    public let lastMessage: Message?
    public let unreadCount: Int
}

public enum ConversationStatus: String, Codable {
    case active
    case pending
    case closed
    case archived
}

// MARK: - Message

public struct Message: Codable, Equatable, Identifiable {
    public let id: String
    public let conversationId: String
    public let senderId: String
    public let senderType: MessageSender
    public let content: String
    public let type: MessageType
    public let metadata: [String: AnyCodable]?
    public let createdAt: Date
    public let isRead: Bool
}

public enum MessageSender: String, Codable {
    case user
    case visitor
    case system
    case ai
}

public enum MessageType: String, Codable {
    case text
    case image
    case file
    case system
}

public struct SendMessageRequest: Codable {
    public let content: String
    public let type: MessageType
    public let metadata: [String: AnyCodable]?
    
    public init(
        content: String,
        type: MessageType = .text,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.content = content
        self.type = type
        self.metadata = metadata
    }
}

// MARK: - Pagination

public struct PaginatedResponse<T: Codable>: Codable {
    public let items: [T]
    public let page: Int
    public let limit: Int
    public let total: Int
    public let totalPages: Int
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable, Equatable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
    
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
