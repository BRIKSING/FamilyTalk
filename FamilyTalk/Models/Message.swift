//
//  Message.swift
//  FamilyTalk
//

import Foundation

enum MessageType: String, Codable {
    case text = "TEXT"
    case system = "SYSTEM"
}

// Embedded in Message for reply context
struct MessageReplyPreview: Codable, Equatable {
    let id: String
    let senderId: String
    var content: String?
    let type: MessageType
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }
}

struct Message: Identifiable, Codable, Equatable {
    // var id allows updating optimistic messages after server ack
    var id: String
    let chatId: String
    let senderId: String
    let type: MessageType
    var content: String?
    var replyToId: String?
    var editedAt: Date?
    var deletedAt: Date?
    let createdAt: Date
    var sender: User?
    var replyTo: MessageReplyPreview?

    var isDeleted: Bool { deletedAt != nil }
    var isEdited: Bool { editedAt != nil }

    var displayContent: String {
        if isDeleted { return "Сообщение удалено" }
        return content ?? ""
    }
}
