//
//  FamilyTalkApp.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import SwiftUI

@main
struct FamilyTalkApp: App {
    @State private var authService = AuthService.shared

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                TabView {
                    ChatsListView()
                        .tabItem { Label("Чаты", systemImage: "message.fill") }

                    ContactsView()
                        .tabItem { Label("Контакты", systemImage: "person.2.fill") }
                }
            } else {
                AuthView()
            }
        }
    }
}
