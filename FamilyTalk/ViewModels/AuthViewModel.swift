//
//  AuthViewModel.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class AuthViewModel {
    var phone = ""
    var displayName = ""
    var isLoading = false
    var errorMessage: String?

    var isFormValid: Bool {
        !phone.isEmpty && phone.count >= 11 && !displayName.isEmpty
    }

    func login() {
        guard isFormValid else {
            errorMessage = "Заполните все поля"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await AuthService.shared.login(phone: phone, displayName: displayName)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func formatPhone() {
        if phone.hasPrefix("8") && phone.count > 1 {
            phone = "+7" + phone.dropFirst()
        } else if !phone.hasPrefix("+") && !phone.isEmpty {
            phone = "+7" + phone
        }
    }
}
