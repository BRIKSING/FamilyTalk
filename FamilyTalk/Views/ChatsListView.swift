//
//  ChatsListView.swift
//  FamilyTalk
//

import SwiftUI

struct ChatsListView: View {
    @State private var viewModel = ChatsListViewModel()
    @State private var selectedChat: Chat?
    @State private var showingNewChatSheet = false
    @State private var newChatError: String?

    private var currentUserId: String { AuthService.shared.currentUser?.id ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.chats.isEmpty {
                    ProgressView()
                } else if viewModel.chats.isEmpty {
                    ContentUnavailableView(
                        "Нет чатов",
                        systemImage: "message",
                        description: Text("Начните разговор с контактом")
                    )
                } else {
                    List(viewModel.chats) { chat in
                        Button {
                            selectedChat = chat
                        } label: {
                            ChatListRow(chat: chat, currentUserId: currentUserId)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .refreshable { await viewModel.fetchChats() }
                }
            }
            .navigationTitle("Чаты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewChatSheet = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(item: $selectedChat) { chat in
                ChatView(viewModel: ChatViewModel(chat: chat))
            }
            .sheet(isPresented: $showingNewChatSheet) {
                NewChatContactPicker { user in
                    Task {
                        do {
                            let chat = try await viewModel.createDirectChat(with: user)
                            showingNewChatSheet = false
                            selectedChat = chat
                        } catch {
                            newChatError = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Ошибка", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let e = viewModel.errorMessage { Text(e) }
            }
            .alert("Ошибка", isPresented: .constant(newChatError != nil)) {
                Button("OK") { newChatError = nil }
            } message: {
                if let e = newChatError { Text(e) }
            }
        }
        // Update chat list when a new message arrives via socket
        .onChange(of: SocketService.shared.newMessage) { _, event in
            guard let event else { return }
            viewModel.applyNewMessage(event)
            // Don't nil out here — ChatView also needs to see it
        }
    }
}

// MARK: - Chat List Row

struct ChatListRow: View {
    let chat: Chat
    let currentUserId: String

    private var title: String { chat.displayName(currentUserId: currentUserId) }

    private var subtitle: String {
        guard let msg = chat.lastMessage else { return "Нет сообщений" }
        if msg.isDeleted { return "Сообщение удалено" }
        if msg.type == .system { return msg.content ?? "" }
        let prefix = msg.senderId == currentUserId ? "Вы: " : ""
        return prefix + (msg.content ?? "")
    }

    private var timestamp: String {
        let date = chat.lastMessage?.createdAt ?? chat.createdAt
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Вчера"
        } else {
            let f = DateFormatter()
            f.dateFormat = "dd.MM"
            return f.string(from: date)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(chat.type == .group ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(String(title.prefix(1)).uppercased())
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(chat.type == .group ? .purple : .blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Contact Picker for New Chat

struct NewChatContactPicker: View {
    let onSelect: (User) -> Void

    @State private var viewModel = ContactsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.filteredContacts.isEmpty {
                    ContentUnavailableView("Нет контактов", systemImage: "person.slash")
                } else {
                    List(viewModel.filteredContacts) { user in
                        Button {
                            onSelect(user)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Text(String(user.displayName.prefix(1)).uppercased())
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.blue)
                                    }
                                VStack(alignment: .leading) {
                                    Text(user.displayName).font(.headline)
                                    if let username = user.username {
                                        Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .searchable(text: $viewModel.searchQuery, prompt: "Поиск")
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        Task { await viewModel.searchUsers() }
                    }
                }
            }
            .navigationTitle("Новый чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ChatsListView()
}
