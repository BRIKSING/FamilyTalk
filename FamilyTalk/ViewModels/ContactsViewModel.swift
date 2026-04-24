//
//  ContactsViewModel.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class ContactsViewModel {
    var contacts: [User] = []
    var searchQuery = ""
    var isLoading = false
    var errorMessage: String?

    private let service = ContactsService.shared

    var filteredContacts: [User] {
        guard !searchQuery.isEmpty else { return contacts }
        return contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchQuery) ||
            ($0.username?.localizedCaseInsensitiveContains(searchQuery) ?? false)
        }
    }

    init() {
        Task { await fetchContacts() }
    }

    func fetchContacts() async {
        isLoading = true
        errorMessage = nil
        do {
            contacts = try await service.fetchContacts()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func searchUsers() async {
        guard !searchQuery.isEmpty else {
            await fetchContacts()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            contacts = try await service.searchUsers(query: searchQuery)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
