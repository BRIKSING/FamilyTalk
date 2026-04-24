//
//  MockData.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation

#if DEBUG
struct MockData {
    static let users: [User] = [
        User(
            id: "1",
            displayName: "Иван Иванов",
            phone: "+79991234567",
            username: "ivan_ivanov",
            bio: "Семейный админ",
            lastSeen: Date().addingTimeInterval(-20)
        ),
        User(
            id: "2",
            displayName: "Мария Петрова",
            phone: "+79991234568",
            username: "maria_p",
            lastSeen: Date().addingTimeInterval(-300)
        ),
        User(
            id: "3",
            displayName: "Пётр Сидоров",
            phone: "+79991234569",
            bio: "Разработчик",
            lastSeen: Date().addingTimeInterval(-3600)
        ),
        User(
            id: "4",
            displayName: "Анна Козлова",
            phone: "+79991234570",
            username: "anna_k",
            lastSeen: Date().addingTimeInterval(-86400)
        ),
        User(
            id: "5",
            displayName: "Дмитрий Грамотеев",
            phone: "+79991234571",
            username: "dmitry_g",
            bio: "iOS разработчик",
            lastSeen: Date().addingTimeInterval(-10)
        )
    ]

    static let callLogs: [CallLog] = [
        CallLog(
            id: "call-1",
            initiatorId: "1",
            targetId: "2",
            type: .voice,
            status: .accepted,
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date().addingTimeInterval(-3300),
            createdAt: Date().addingTimeInterval(-3610)
        ),
        CallLog(
            id: "call-2",
            initiatorId: "2",
            targetId: "1",
            type: .video,
            status: .missed,
            startedAt: nil,
            endedAt: nil,
            createdAt: Date().addingTimeInterval(-7200)
        ),
        CallLog(
            id: "call-3",
            initiatorId: "3",
            targetId: "1",
            type: .voice,
            status: .declined,
            startedAt: nil,
            endedAt: nil,
            createdAt: Date().addingTimeInterval(-10800)
        )
    ]

    static let currentUser = User(
        id: "current-user",
        displayName: "Я",
        phone: "+79999999999",
        username: "me",
        bio: "Это я!",
        lastSeen: Date()
    )

    static let authResponse = AuthResponse(
        accessToken: "mock-access-token",
        user: currentUser
    )
}
#endif
