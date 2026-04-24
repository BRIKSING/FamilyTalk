//
//  ChatViewModel.swift
//  FamilyTalk
//

import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {
    let chat: Chat
    var messages: [Message] = []
    var inputText = ""
    var replyingTo: Message?
    var isLoading = false
    var isSending = false
    var errorMessage: String?
    var nextCursor: String?
    var hasMore = true

    // userId → displayName for typing indicator
    var typingUsers: [String: String] = [:]

    private let service = ChatService.shared
    private var pendingLocalId: String?
    private var typingTimer: Timer?
    private var isTypingActive = false

    var typingText: String? {
        guard !typingUsers.isEmpty else { return nil }
        let names = typingUsers.values.prefix(2).joined(separator: ", ")
        return "\(names) печатает…"
    }

    var currentUserId: String { AuthService.shared.currentUser?.id ?? "" }

    init(chat: Chat) {
        self.chat = chat
        Task { await loadMessages() }
    }

    // MARK: - Load Messages (REST)

    func loadMessages() async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await service.fetchMessages(chatId: chat.id)
            // Server returns newest first → reverse for display (oldest at top)
            messages = page.items.reversed()
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreMessages() async {
        guard hasMore, let cursor = nextCursor, !isLoading else { return }
        isLoading = true
        do {
            let page = try await service.fetchMessages(chatId: chat.id, cursor: cursor)
            messages.insert(contentsOf: page.items.reversed(), at: 0)
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Send Message (Socket)

    func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        inputText = ""
        isSending = true
        stopTyping()

        let localId = UUID().uuidString
        pendingLocalId = localId

        // Optimistic append
        var optimistic = Message(
            id: localId,
            chatId: chat.id,
            senderId: currentUserId,
            type: .text,
            content: content,
            replyToId: replyingTo?.id,
            createdAt: Date()
        )
        optimistic.sender = AuthService.shared.currentUser
        optimistic.replyTo = replyingTo.map {
            MessageReplyPreview(id: $0.id, senderId: $0.senderId, content: $0.content,
                                type: $0.type, deletedAt: $0.deletedAt)
        }
        messages.append(optimistic)
        replyingTo = nil

        SocketService.shared.sendMessage(chatId: chat.id, content: content, replyToId: optimistic.replyToId) { [weak self] success in
            self?.isSending = false
            if !success {
                self?.messages.removeAll { $0.id == localId }
                self?.errorMessage = "Не удалось отправить сообщение"
                self?.pendingLocalId = nil
            }
        }
    }

    // MARK: - Socket Event Handlers

    func handleNewMessage(_ event: NewMessageEvent) {
        guard event.chatId == chat.id else { return }
        // Avoid duplicates with the ack-updated optimistic message
        guard !messages.contains(where: { $0.id == event.message.id }) else { return }
        messages.append(event.message)
        // Auto-mark as read
        SocketService.shared.sendRead(chatId: chat.id, messageId: event.message.id)
    }

    func handleMessageAck(_ event: MessageAckEvent) {
        guard event.chatId == chat.id,
              let localId = pendingLocalId,
              let idx = messages.firstIndex(where: { $0.id == localId }) else { return }
        messages[idx].id = event.messageId
        pendingLocalId = nil
    }

    func handleTypingStart(userId: String) {
        guard userId != currentUserId else { return }
        let name = chat.members.first { $0.userId == userId }?.user?.displayName ?? userId
        typingUsers[userId] = name
    }

    func handleTypingStop(userId: String) {
        typingUsers.removeValue(forKey: userId)
    }

    // MARK: - Typing

    func handleTyping() {
        if !isTypingActive {
            isTypingActive = true
            SocketService.shared.sendTypingStart(chatId: chat.id)
        }
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopTyping() }
        }
    }

    private func stopTyping() {
        guard isTypingActive else { return }
        isTypingActive = false
        typingTimer?.invalidate()
        typingTimer = nil
        SocketService.shared.sendTypingStop(chatId: chat.id)
    }

    // MARK: - Edit / Delete (REST)

    func editMessage(_ message: Message, newContent: String) async {
        do {
            let updated = try await service.editMessage(chatId: chat.id, messageId: message.id, content: newContent)
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMessage(_ message: Message, forAll: Bool = false) async {
        do {
            try await service.deleteMessage(chatId: chat.id, messageId: message.id, forAll: forAll)
            if forAll {
                if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[idx].content = nil
                    messages[idx].deletedAt = Date()
                }
            } else {
                messages.removeAll { $0.id == message.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mark Read

    func markRead() {
        guard let lastId = messages.last?.id else { return }
        SocketService.shared.sendRead(chatId: chat.id, messageId: lastId)
    }
}
