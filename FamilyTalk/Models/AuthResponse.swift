//
//  AuthResponse.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation

// POST /auth/login → { accessToken, user }
struct AuthResponse: Codable {
    let accessToken: String
    let user: User
}

// POST /auth/login request body
struct LoginRequest: Codable {
    let phone: String
    let displayName: String
}
