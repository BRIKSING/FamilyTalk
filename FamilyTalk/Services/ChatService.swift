//
//  ChatService.swift
//  FamilyTalk
//

import Foundation

// MARK: - Response wrappers

private struct ChatsResponse: Codable {
    let chats: [Chat]
}

struct MessagesPage: Codable {
    let items: [Message]
    let nextCursor: String?
}

// MARK: - Request bodies

private struct CreateDirectChatRequest: Encodable {
    let type = "DIRECT"
    let targetUserId: String
}

private struct CreateGroupChatRequest: Encodable {
    let type = "GROUP"
    let name: String
    let memberIds: [String]
}

private struct EditMessageRequest: Codable {
    let content: String
}

private struct DeleteMessageRequest: Codable {
    let forAll: Bool
}

// MARK: - Service

final class ChatService {
    static let shared = ChatService()
    private let network = NetworkService.shared
    private init() {}

    // MARK: - GET /chats

    func fetchChats() async throws -> [Chat] {
        let response: ChatsResponse = try await network.request(endpoint: "/chats")
        return response.chats
    }

    // MARK: - POST /chats (DIRECT)

    func createDirectChat(targetUserId: String) async throws -> Chat {
        return try await network.request(
            endpoint: "/chats",
            method: "POST",
            body: CreateDirectChatRequest(targetUserId: targetUserId)
        )
    }

    // MARK: - POST /chats (GROUP)

    func createGroupChat(name: String, memberIds: [String]) async throws -> Chat {
        return try await network.request(
            endpoint: "/chats",
            method: "POST",
            body: CreateGroupChatRequest(name: name, memberIds: memberIds)
        )
    }

    // MARK: - GET /chats/:id/messages

    func fetchMessages(chatId: String, cursor: String? = nil, limit: Int = 50) async throws -> MessagesPage {
        var queryItems = [URLQueryItem(name: "limit", value: "\(min(limit, 100))")]
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await network.request(
            endpoint: "/chats/\(chatId)/messages",
            queryItems: queryItems
        )
    }

    // MARK: - PATCH /chats/:id/messages/:msgId

    func editMessage(chatId: String, messageId: String, content: String) async throws -> Message {
        return try await network.request(
            endpoint: "/chats/\(chatId)/messages/\(messageId)",
            method: "PATCH",
            body: EditMessageRequest(content: content)
        )
    }

    // MARK: - DELETE /chats/:id/messages/:msgId

    func deleteMessage(chatId: String, messageId: String, forAll: Bool = false) async throws {
        struct OkResponse: Codable { let ok: Bool }
        let _: OkResponse = try await network.request(
            endpoint: "/chats/\(chatId)/messages/\(messageId)",
            method: "DELETE",
            body: DeleteMessageRequest(forAll: forAll)
        )
    }
}
