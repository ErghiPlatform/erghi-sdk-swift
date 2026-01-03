# AI Chat Swift SDK

Official Swift SDK for AI Chat - Build AI-powered chat experiences in your iOS, macOS, tvOS, and watchOS apps.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-blue.svg)](https://developer.apple.com)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager)

## Features

- ✅ 100% Swift with async/await support
- 🔐 JWT authentication with auto-refresh
- 💬 Real-time messaging with WebSocket (Starscream)
- 📱 iOS 15+, macOS 12+, tvOS 15+, watchOS 8+
- 🎯 Type-safe with Codable models
- 🔄 Combine framework integration
- 📦 Swift Package Manager support
- 🧪 Fully tested

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/aichat/swift-sdk.git", from: "1.0.0")
]
```

Or in Xcode:
1. File > Add Package Dependencies
2. Enter: `https://github.com/aichat/swift-sdk.git`

## Quick Start

### Initialize the Client

```swift
import AIChatSDK

let client = AIChatClient(
    config: AIChatConfig(
        apiURL: URL(string: "https://api.aichat.com")!,
        debug: true
    )
)
```

### Authentication

```swift
// Register
let auth = try await client.auth.register(
    RegisterRequest(
        email: "user@example.com",
        password: "SecurePass123!",
        firstName: "John",
        lastName: "Doe"
    )
)

// Login
let auth = try await client.auth.login(
    LoginRequest(
        email: "user@example.com",
        password: "SecurePass123!"
    )
)

// Get current user
let user = try await client.auth.me()

// Logout
try await client.auth.logout()
```

### Chat Operations

```swift
// Create conversation
let conversation = try await client.chat.createConversation(
    widgetId: "your-widget-id",
    metadata: ["page": AnyCodable("/products")]
)

// Get messages
let messages = try await client.chat.getMessages(
    conversationId: conversation.id,
    page: 1,
    limit: 50
)

// Send message
let message = try await client.chat.sendMessage(
    conversationId: conversation.id,
    request: SendMessageRequest(content: "Hello!")
)

// Mark as read
try await client.chat.markAsRead(conversationId: conversation.id)
```

### Real-Time with WebSocket & Combine

```swift
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    private let client: AIChatClient
    private var cancellables = Set<AnyCancellable>()
    
    init(client: AIChatClient) {
        self.client = client
        setupWebSocket()
    }
    
    private func setupWebSocket() {
        // Connect WebSocket
        client.connectWebSocket()
        
        // Subscribe to messages
        client.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.messages.append(message)
            }
            .store(in: &cancellables)
        
        // Join conversation
        client.joinConversation("conversation-id")
    }
    
    func sendMessage(_ text: String) async {
        client.sendTyping(conversationId: "conversation-id")
        
        let message = try? await client.chat.sendMessage(
            conversationId: "conversation-id",
            request: SendMessageRequest(content: text)
        )
    }
}
```

## SwiftUI Example

```swift
import SwiftUI
import AIChatSDK

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var messageText = ""
    
    init(client: AIChatClient) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(client: client))
    }
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack {
                    ForEach(viewModel.messages) { message in
                        MessageRow(message: message)
                    }
                }
            }
            
            HStack {
                TextField("Type a message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                
                Button("Send") {
                    Task {
                        await viewModel.sendMessage(messageText)
                        messageText = ""
                    }
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Chat")
    }
}

struct MessageRow: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.senderType == .user {
                Spacer()
            }
            
            VStack(alignment: .leading) {
                Text(message.content)
                    .padding()
                    .background(message.senderType == .user ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                
                Text(message.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if message.senderType != .user {
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}
```

## Error Handling

```swift
do {
    try await client.auth.login(
        LoginRequest(email: "user@example.com", password: "wrong")
    )
} catch AIChatError.authenticationFailed(let message) {
    print("Auth error: \(message)")
} catch AIChatError.networkError(let message) {
    print("Network error: \(message)")
} catch {
    print("Error: \(error)")
}
```

## API Documentation

### AIChatClient

- `auth` - Authentication operations
- `chat` - Chat operations
- `connectWebSocket()` - Connect to real-time updates
- `disconnectWebSocket()` - Disconnect WebSocket
- `messagePublisher` - Combine publisher for real-time messages
- `sendTyping()` - Send typing indicator
- `joinConversation()` - Join conversation room
- `leaveConversation()` - Leave conversation room

### Models

- `User` - User model
- `AuthResponse` - Authentication response
- `Conversation` - Conversation model
- `Message` - Message model
- `PaginatedResponse<T>` - Paginated data

### Errors

- `AIChatError.authenticationFailed` - Auth errors
- `AIChatError.networkError` - Network errors
- `AIChatError.validationError` - Validation errors
- `AIChatError.notFound` - Resource not found
- `AIChatError.webSocketError` - WebSocket errors

## Development

```bash
# Build
swift build

# Run tests
swift test

# Generate documentation
swift package generate-documentation
```

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+
- Xcode 15.0+

## Contributing

Contributions are welcome! Please read our [contributing guide](CONTRIBUTING.md).

## License

MIT License - see [LICENSE](LICENSE) file

## Support

- 📧 Email: support@aichat.com
- 💬 Discord: [Join our community](https://discord.gg/aichat)
- 📝 Issues: [GitHub Issues](https://github.com/aichat/swift-sdk/issues)

---

Made with ❤️ by the AI Chat team
