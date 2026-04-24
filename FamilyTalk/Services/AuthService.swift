//
//  AuthService.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation
import Observation

@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var currentUser: User?
    private(set) var isAuthenticated = false

    private let network = NetworkService.shared
    private let keychain = KeychainService.shared
    private var unauthorizedObserver: (any NSObjectProtocol)?

    private init() {
        restoreSession()
        unauthorizedObserver = NotificationCenter.default.addObserver(
            forName: .networkUnauthorized,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.logout() }
        }
    }

    // MARK: - POST /auth/login

    func login(phone: String, displayName: String) async throws -> User {
        let response: AuthResponse = try await network.request(
            endpoint: "/auth/login",
            method: "POST",
            body: LoginRequest(phone: phone, displayName: displayName),
            requiresAuth: false
        )
        await MainActor.run { saveSession(response) }
        return response.user
    }

    // MARK: - GET /auth/me

    func fetchMe() async throws -> User {
        let user: User = try await network.request(endpoint: "/auth/me")
        await MainActor.run { currentUser = user }
        return user
    }

    // MARK: - Logout

    @MainActor
    func logout() {
        keychain.delete(key: "access_token")
        UserDefaults.standard.removeObject(forKey: "current_user")
        network.clearAccessToken()
        SocketService.shared.disconnect()
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Private

    @MainActor
    private func saveSession(_ response: AuthResponse) {
        keychain.save(key: "access_token", value: response.accessToken)
        network.setAccessToken(response.accessToken)
        if let data = try? JSONEncoder().encode(response.user) {
            UserDefaults.standard.set(data, forKey: "current_user")
        }
        currentUser = response.user
        isAuthenticated = true
        SocketService.shared.connect(token: response.accessToken)
    }

    private func restoreSession() {
        guard let token = keychain.load(key: "access_token"),
              let data = UserDefaults.standard.data(forKey: "current_user"),
              let user = try? JSONDecoder().decode(User.self, from: data) else { return }
        network.setAccessToken(token)
        currentUser = user
        isAuthenticated = true
        SocketService.shared.connect(token: token)
    }
}
