//
//  ChatsListViewModel.swift
//  FamilyTalk
//

import Foundation
import Observation

@Observable
@MainActor
final class ChatsListViewModel {
    var chats: [Chat] = []
    var isLoading = false
    var errorMessage: String?

    private let service = ChatService.shared

    init() {
        Task { await fetchChats() }
    }

    func fetchChats() async {
        isLoading = true
        errorMessage = nil
        do {
            chats = try await service.fetchChats()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createDirectChat(with user: User) async throws -> Chat {
        let chat = try await service.createDirectChat(targetUserId: user.id)
        // Prepend new chat to list if not already present
        if !chats.contains(where: { $0.id == chat.id }) {
            chats.insert(chat, at: 0)
        }
        return chat
    }

    /// Update lastMessage and unread count when a new socket message arrives
    func applyNewMessage(_ event: NewMessageEvent) {
        guard let idx = chats.firstIndex(where: { $0.id == event.chatId }) else { return }
        chats[idx].lastMessage = event.message
        let isOwnMessage = event.message.senderId == AuthService.shared.currentUser?.id
        if !isOwnMessage {
            chats[idx].unreadCount += 1
        }
        // Bubble chat to top
        let updated = chats.remove(at: idx)
        chats.insert(updated, at: 0)
    }
}
