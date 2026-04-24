//
//  ContactsService.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation
import CryptoKit

// MARK: - Response Wrappers

private struct ContactsResponse: Codable {
    let contacts: [User]
}

private struct UsersResponse: Codable {
    let users: [User]
}

private struct OkResponse: Codable {
    let ok: Bool
}

// MARK: - Request Bodies

private struct ContactSyncRequest: Codable {
    let hashes: [String]
}

private struct UpdateProfileRequest: Codable {
    var displayName: String?
    var username: String?
    var bio: String?
}

// MARK: - Service

final class ContactsService {
    static let shared = ContactsService()
    private let network = NetworkService.shared
    private init() {}

    // MARK: - GET /users/contacts

    func fetchContacts() async throws -> [User] {
        let response: ContactsResponse = try await network.request(endpoint: "/users/contacts")
        return response.contacts
    }

    // MARK: - POST /users/contacts/sync
    // Hashes phone numbers locally with SHA-256 before sending

    func syncContacts(phoneNumbers: [String]) async throws -> [User] {
        let hashes = phoneNumbers.map { sha256($0) }
        let response: ContactsResponse = try await network.request(
            endpoint: "/users/contacts/sync",
            method: "POST",
            body: ContactSyncRequest(hashes: hashes)
        )
        return response.contacts
    }

    // MARK: - GET /users/search?q=

    func searchUsers(query: String) async throws -> [User] {
        let response: UsersResponse = try await network.request(
            endpoint: "/users/search",
            queryItems: [URLQueryItem(name: "q", value: query)]
        )
        return response.users
    }

    // MARK: - POST /users/:id/block

    func blockUser(id: String) async throws {
        let _: OkResponse = try await network.request(
            endpoint: "/users/\(id)/block",
            method: "POST"
        )
    }

    // MARK: - DELETE /users/:id/block

    func unblockUser(id: String) async throws {
        let _: OkResponse = try await network.request(
            endpoint: "/users/\(id)/block",
            method: "DELETE"
        )
    }

    // MARK: - GET /users/blocked

    func fetchBlocked() async throws -> [User] {
        let response: UsersResponse = try await network.request(endpoint: "/users/blocked")
        return response.users
    }

    // MARK: - PATCH /users/me

    func updateProfile(
        displayName: String? = nil,
        username: String? = nil,
        bio: String? = nil
    ) async throws -> User {
        return try await network.request(
            endpoint: "/users/me",
            method: "PATCH",
            body: UpdateProfileRequest(displayName: displayName, username: username, bio: bio)
        )
    }

    // MARK: - Private

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
