//
//  Chat.swift
//  FamilyTalk
//

import Foundation

enum ChatType: String, Codable {
    case direct = "DIRECT"
    case group = "GROUP"
}

struct ChatMember: Codable, Identifiable {
    var id: String { userId }
    let chatId: String
    let userId: String
    let joinedAt: Date
    var user: User?
}

struct Chat: Identifiable, Codable, Hashable {
    let id: String
    let type: ChatType
    var name: String?
    var avatarUrl: String?
    let createdAt: Date
    var members: [ChatMember]
    var lastMessage: Message?
    var unreadCount: Int

    func displayName(currentUserId: String) -> String {
        if type == .group { return name ?? "Групповой чат" }
        return members.first { $0.userId != currentUserId }?.user?.displayName ?? "Чат"
    }

    func otherUser(currentUserId: String) -> User? {
        members.first { $0.userId != currentUserId }?.user
    }

    static func == (lhs: Chat, rhs: Chat) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
