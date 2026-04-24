//
//  CallService.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation

// GET /calls/history response
struct CallHistoryPage: Codable {
    let items: [CallLog]
    let nextCursor: String?
}

final class CallService {
    static let shared = CallService()
    private let network = NetworkService.shared
    private init() {}

    // MARK: - GET /calls/history
    // Call signaling (offer/answer/hangup) goes through SocketService, not REST

    func fetchHistory(cursor: String? = nil, limit: Int = 20) async throws -> CallHistoryPage {
        var items = [URLQueryItem(name: "limit", value: "\(min(limit, 100))")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await network.request(endpoint: "/calls/history", queryItems: items)
    }
}
