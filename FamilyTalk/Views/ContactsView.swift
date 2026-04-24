//
//  ContactsView.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import SwiftUI

struct ContactsView: View {
    @State private var viewModel = ContactsViewModel()
    @State private var callViewModel = CallViewModel()
    @State private var selectedUser: User?
    @State private var selectedCallType: CallType = .voice
    @State private var showingCallScreen = false
    @State private var showingIncomingCall = false
    @State private var selectedChat: Chat?
    @State private var chatError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    ForEach(viewModel.filteredContacts) { user in
                        ContactRow(user: user) { callType in
                            selectedUser = user
                            selectedCallType = callType
                            showingCallScreen = true
                        } onMessageTapped: {
                            Task {
                                do {
                                    let chat = try await ChatService.shared.createDirectChat(targetUserId: user.id)
                                    selectedChat = chat
                                } catch {
                                    chatError = error.localizedDescription
                                }
                            }
                        }
                    }
                }
                .searchable(text: $viewModel.searchQuery, prompt: "Поиск контактов")
                .refreshable {
                    await viewModel.fetchContacts()
                }
                .navigationTitle("Контакты")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            AuthService.shared.logout()
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                if viewModel.isLoading {
                    ProgressView().scaleEffect(1.5)
                }
            }
            .navigationDestination(item: $selectedChat) { chat in
                    ChatView(viewModel: ChatViewModel(chat: chat))
                }
            .sheet(isPresented: $showingCallScreen) {
                if let user = selectedUser {
                    CallView(viewModel: callViewModel, targetUser: user, callType: selectedCallType)
                        .onDisappear { callViewModel.reset() }
                }
            }
            // Incoming call — show call screen with the caller as target
            .onChange(of: SocketService.shared.incomingCall) { _, event in
                guard let event else { return }
                callViewModel.handleIncomingCall(event)
                // Find caller in contacts list (may not be there yet)
                selectedUser = viewModel.contacts.first { $0.id == event.initiatorId }
                    ?? User(id: event.initiatorId, displayName: event.initiatorId)
                selectedCallType = event.type
                showingCallScreen = true
                SocketService.shared.incomingCall = nil
            }
            .alert("Ошибка", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage { Text(error) }
            }
            .alert("Ошибка", isPresented: .constant(chatError != nil)) {
                Button("OK") { chatError = nil }
            } message: {
                if let e = chatError { Text(e) }
            }
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let user: User
    let onCallTapped: (CallType) -> Void
    let onMessageTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.headline)

                HStack(spacing: 4) {
                    if user.isOnline {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("онлайн").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(user.lastSeenText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Button { onMessageTapped() } label: {
                    Image(systemName: "message.fill").foregroundStyle(.orange).font(.title3)
                }
                .buttonStyle(.plain)

                Button { onCallTapped(.voice) } label: {
                    Image(systemName: "phone.fill").foregroundStyle(.green).font(.title3)
                }
                .buttonStyle(.plain)

                Button { onCallTapped(.video) } label: {
                    Image(systemName: "video.fill").foregroundStyle(.blue).font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContactsView()
}
