//
//  CallLog.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation

enum CallType: String, Codable {
    case voice = "VOICE"
    case video = "VIDEO"
}

enum CallStatus: String, Codable {
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case missed = "MISSED"
}

struct CallLog: Identifiable, Codable {
    let id: String
    let initiatorId: String
    let targetId: String
    let type: CallType
    let status: CallStatus?
    let startedAt: Date?
    let endedAt: Date?
    let createdAt: Date
    var initiator: User?
    var target: User?

    var duration: TimeInterval? {
        guard let s = startedAt, let e = endedAt else { return nil }
        return e.timeIntervalSince(s)
    }

    var durationText: String {
        guard let d = duration else { return "—" }
        return String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}
