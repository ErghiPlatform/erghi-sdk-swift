// Erghi Swift SDK — Simulation / Integration Example
//
// A command-line program demonstrating the full chat flow against a locally
// running Erghi stack (http://localhost:5000).
//
// Run:
//   swift run ErghiExample

import Foundation
import Combine
import AIChatSDK

let timestamp = Int(Date().timeIntervalSince1970)
let testEmail = "demo_\(timestamp)@erghi.dev"
let testPassword = "Demo@12345!"

// Combine cancellables bag
var cancellables = Set<AnyCancellable>()

// Semaphore so the command-line process stays alive
let done = DispatchSemaphore(value: 0)

// ── Main async task ──────────────────────────────────────────────────────────

Task {
    print("=== Erghi Swift SDK Simulation ===\n")

    let client = AIChatClient(config: AIChatConfig(
        apiUrl: "http://localhost:5000",
        debug: true
    ))

    do {
        // ── 1. Register ──────────────────────────────────────────────────────
        print("▶ Registering: \(testEmail)")
        let authResponse = try await client.auth.register(
            email: testEmail,
            password: testPassword,
            firstName: "Demo",
            lastName: "User"
        )
        print("✓ Registered. Token type: \(authResponse.tokenType)")
        print("  User ID: \(authResponse.user.id)")

        // ── 2. Login ─────────────────────────────────────────────────────────
        print("\n▶ Logging in…")
        let login = try await client.auth.login(email: testEmail, password: testPassword)
        let tokenPreview = String(login.accessToken.prefix(20))
        print("✓ Logged in. Token (truncated): \(tokenPreview)…")

        // ── 3. Create workspace ───────────────────────────────────────────────
        print("\n▶ Creating workspace…")
        let workspace = try await client.workspace.create(
            name: "Demo Workspace \(timestamp)"
        )
        print("✓ Workspace: \(workspace.id) / \(workspace.name)")

        // ── 4. Create conversation ────────────────────────────────────────────
        print("\n▶ Creating conversation…")
        let conversation = try await client.chat.createConversation(
            widgetId: "demo-widget",
            metadata: ["source": "swift-simulation"]
        )
        print("✓ Conversation: \(conversation.id) / status: \(conversation.status)")

        // ── 5. Subscribe to real-time messages via Combine ───────────────────
        print("\n▶ Subscribing to message publisher…")
        client.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { msg in
                print("  📨 [REALTIME] \(msg.sender): \"\(msg.content)\"")
            }
            .store(in: &cancellables)

        client.typingPublisher
            .receive(on: DispatchQueue.main)
            .sink { evt in
                print("  ✍️  [REALTIME] \(evt.userId) typing: \(evt.isTyping)")
            }
            .store(in: &cancellables)

        // ── 6. Connect WebSocket ──────────────────────────────────────────────
        print("\n▶ Connecting to hub…")
        try await client.connect()
        print("✓ Hub connected")

        // ── 7. Join conversation room ─────────────────────────────────────────
        try await client.joinConversation(conversation.id)
        print("✓ Joined conversation room")

        // ── 8. Send messages ──────────────────────────────────────────────────
        let messages = [
            "Hello from the Swift SDK simulation!",
            "Can you help me with my order?",
            "What are your business hours?"
        ]

        print("\n▶ Sending messages…")
        for content in messages {
            let msg = try await client.chat.sendMessage(
                conversationId: conversation.id,
                content: content
            )
            print("  ✓ Sent [\(msg.id)]: \"\(msg.content)\"")
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        }

        // ── 9. Fetch message history ──────────────────────────────────────────
        print("\n▶ Fetching message history…")
        let history = try await client.chat.getMessages(conversationId: conversation.id)
        print("  ✓ \(history.data.count) messages (total: \(history.total))")

        // ── 10. Typing indicator ──────────────────────────────────────────────
        print("\n▶ Sending typing indicators…")
        try await client.sendTyping(conversationId: conversation.id, isTyping: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        try await client.sendTyping(conversationId: conversation.id, isTyping: false)
        print("  ✓ Done")

        // ── 11. Close conversation ─────────────────────────────────────────────
        print("\n▶ Closing conversation…")
        let closed = try await client.chat.closeConversation(conversationId: conversation.id)
        print("  ✓ Status: \(closed.status)")

        // ── 12. Disconnect ─────────────────────────────────────────────────────
        await client.disconnect()
        print("\n✅ Simulation complete!")

    } catch {
        print("❌ Error: \(error)")
    }

    done.signal()
}

done.wait()
