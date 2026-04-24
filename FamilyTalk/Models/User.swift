//
//  User.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation

struct User: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var phone: String?
    var username: String?
    var avatarUrl: String?
    var bio: String?
    var lastSeen: Date?

    var isOnline: Bool {
        guard let lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < 30
    }

    var lastSeenText: String {
        guard let lastSeen else { return "Давно" }
        let interval = Date().timeIntervalSince(lastSeen)
        if interval < 60 { return "только что" }
        if interval < 3600 { return "\(Int(interval / 60)) мин назад" }
        if interval < 86400 { return "\(Int(interval / 3600)) ч назад" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: lastSeen)
    }
}
