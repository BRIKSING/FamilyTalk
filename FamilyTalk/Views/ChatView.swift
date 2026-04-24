//
//  ChatView.swift
//  FamilyTalk
//

import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @State private var editingMessage: Message?
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Pagination — load older messages
                        if viewModel.hasMore {
                            Button {
                                Task { await viewModel.loadMoreMessages() }
                            } label: {
                                if viewModel.isLoading {
                                    ProgressView().frame(maxWidth: .infinity).padding()
                                } else {
                                    Text("Загрузить ранее")
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                }
                            }
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                isOwn: message.senderId == viewModel.currentUserId,
                                showSenderName: viewModel.chat.type == .group
                            )
                            .id(message.id)
                            .contextMenu {
                                messageContextMenu(message)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                    viewModel.markRead()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            // Typing indicator
            if let typing = viewModel.typingText {
                Text(typing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            // Reply preview bar
            if let reply = viewModel.replyingTo {
                ReplyPreviewBar(message: reply) {
                    viewModel.replyingTo = nil
                }
            }

            // Input bar
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(viewModel.chat.displayName(currentUserId: viewModel.currentUserId))
                        .fontWeight(.semibold)
                    if !viewModel.typingUsers.isEmpty {
                        Text("печатает…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Ошибка", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let e = viewModel.errorMessage { Text(e) }
        }
        // Edit sheet
        .alert("Редактировать", isPresented: .constant(editingMessage != nil)) {
            TextField("Текст", text: $editText)
            Button("Сохранить") {
                if let msg = editingMessage {
                    Task { await viewModel.editMessage(msg, newContent: editText) }
                }
                editingMessage = nil
            }
            Button("Отмена", role: .cancel) { editingMessage = nil }
        }
        // Socket event handlers
        .onChange(of: SocketService.shared.newMessage) { _, event in
            guard let event, event.chatId == viewModel.chat.id else { return }
            viewModel.handleNewMessage(event)
            SocketService.shared.newMessage = nil
        }
        .onChange(of: SocketService.shared.messageAck) { _, event in
            guard let event, event.chatId == viewModel.chat.id else { return }
            viewModel.handleMessageAck(event)
            SocketService.shared.messageAck = nil
        }
        .onChange(of: SocketService.shared.typingStart) { _, event in
            guard let event, event.chatId == viewModel.chat.id else { return }
            viewModel.handleTypingStart(userId: event.userId)
            SocketService.shared.typingStart = nil
        }
        .onChange(of: SocketService.shared.typingStop) { _, event in
            guard let event, event.chatId == viewModel.chat.id else { return }
            viewModel.handleTypingStop(userId: event.userId)
            SocketService.shared.typingStop = nil
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение…", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onChange(of: viewModel.inputText) { _, _ in
                    viewModel.handleTyping()
                }

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func messageContextMenu(_ message: Message) -> some View {
        if !message.isDeleted {
            Button {
                viewModel.replyingTo = message
            } label: {
                Label("Ответить", systemImage: "arrowshape.turn.up.left")
            }

            if message.senderId == viewModel.currentUserId {
                Button {
                    editText = message.content ?? ""
                    editingMessage = message
                } label: {
                    Label("Редактировать", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    Task { await viewModel.deleteMessage(message, forAll: false) }
                } label: {
                    Label("Удалить у себя", systemImage: "trash")
                }

                Button(role: .destructive) {
                    Task { await viewModel.deleteMessage(message, forAll: true) }
                } label: {
                    Label("Удалить у всех", systemImage: "trash.fill")
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    let isOwn: Bool
    let showSenderName: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isOwn { Spacer(minLength: 60) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                // Sender name in group chats
                if showSenderName && !isOwn {
                    Text(message.sender?.displayName ?? "")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 4)
                }

                // Reply quote
                if let reply = message.replyTo {
                    ReplyQuoteView(reply: reply, isOwn: isOwn)
                }

                // Bubble
                VStack(alignment: .trailing, spacing: 4) {
                    if message.type == .system {
                        Text(message.content ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    } else if message.isDeleted {
                        Text("Сообщение удалено")
                            .italic()
                            .font(.subheadline)
                            .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isOwn ? Color.blue.opacity(0.5) : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Text(message.content ?? "")
                            .font(.body)
                            .foregroundStyle(isOwn ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isOwn ? Color.blue : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // Timestamp + edited mark
                    if message.type != .system {
                        HStack(spacing: 3) {
                            if message.isEdited {
                                Text("изм.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(message.createdAt, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }

            if !isOwn { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
    }
}

// MARK: - Reply Quote (inside bubble)

struct ReplyQuoteView: View {
    let reply: MessageReplyPreview
    let isOwn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(isOwn ? Color.white.opacity(0.5) : Color.blue)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(reply.isDeleted ? "Удалено" : (reply.content ?? ""))
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(isOwn ? .white.opacity(0.85) : .primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isOwn ? Color.white.opacity(0.15) : Color(.systemGray4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Reply Preview Bar (above input)

struct ReplyPreviewBar: View {
    let message: Message
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(message.sender?.displayName ?? "")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                Text(message.isDeleted ? "Сообщение удалено" : (message.content ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

#Preview {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(chat: Chat(
            id: "1",
            type: .direct,
            name: nil,
            avatarUrl: nil,
            createdAt: Date(),
            members: [],
            lastMessage: nil,
            unreadCount: 0
        )))
    }
}
