//
//  SocketService.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation
import Observation
import SocketIO

// MARK: - Call Event Payloads (Server → Client)

struct IncomingCallEvent: Equatable {
    let callId: String
    let initiatorId: String
    let type: CallType
    let sdp: String
}

struct CallAnsweredEvent: Equatable {
    let callId: String
    let sdp: String
}

struct IceCandidateEvent: Equatable {
    let callId: String
    let fromUserId: String
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int?
    let usernameFragment: String?
}

struct CallHangupEvent: Equatable {
    let callId: String
}

// MARK: - Chat Event Payloads

struct NewMessageEvent: Equatable {
    let message: Message
    var chatId: String { message.chatId }
}

struct MessageAckEvent: Equatable {
    let messageId: String
    let chatId: String
}

struct MessageReadEvent: Equatable {
    let chatId: String
    let messageId: String
    let userId: String
    let readAt: Date
}

struct TypingEvent: Equatable {
    let chatId: String
    let userId: String
}

// MARK: - SocketService

// @unchecked Sendable: socket.io-client-swift is not Swift 6 Sendable-aware;
// thread safety is enforced manually — all mutations go through DispatchQueue.main.
@Observable
final class SocketService: @unchecked Sendable {
    static let shared = SocketService()

    // Connection
    private(set) var isConnected = false

    // Call events (Server → Client)
    var incomingCall: IncomingCallEvent?
    var answeredCall: CallAnsweredEvent?
    var iceCandidate: IceCandidateEvent?
    var remoteHangup: CallHangupEvent?
    var remoteDeclined: CallHangupEvent?

    // Chat events (Server → Client)
    var newMessage: NewMessageEvent?
    var messageAck: MessageAckEvent?
    var messageRead: MessageReadEvent?
    var typingStart: TypingEvent?
    var typingStop: TypingEvent?

    // @ObservationIgnored: @Observable macro must not synthesize storage wrappers
    // for these — they are opaque socket.io objects accessed only from the main thread.
    @ObservationIgnored private var manager: SocketManager?
    @ObservationIgnored private var socket: SocketIOClient?

    // Shared decoder for parsing socket payloads
    @ObservationIgnored private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        return d
    }()

    private init() {}

    // MARK: - Connection

    func connect(token: String) {
        guard let url = URL(string: NetworkService.shared.baseURL) else { return }

        manager = SocketManager(
            socketURL: url,
            config: [
                .log(false),
                .compress,
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(2),
                .forceWebsockets(true),
                .extraHeaders(["Authorization": "Bearer \(token)"])
            ]
        )

        socket = manager?.defaultSocket
        setupHandlers()
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        manager = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    // MARK: - Call Emit

    func sendOffer(targetUserId: String, sdp: String, type: CallType) {
        emit("call:offer", ["targetUserId": targetUserId, "sdp": sdp, "type": type.rawValue])
    }

    func sendAnswer(callId: String, targetUserId: String, sdp: String) {
        emit("call:answer", ["callId": callId, "targetUserId": targetUserId, "sdp": sdp])
    }

    func sendIceCandidate(
        callId: String, targetUserId: String, candidate: String,
        sdpMid: String?, sdpMLineIndex: Int?, usernameFragment: String?
    ) {
        var c: [String: Any] = ["candidate": candidate]
        if let v = sdpMid { c["sdpMid"] = v }
        if let v = sdpMLineIndex { c["sdpMLineIndex"] = v }
        if let v = usernameFragment { c["usernameFragment"] = v }
        emit("call:ice-candidate", ["callId": callId, "targetUserId": targetUserId, "candidate": c])
    }

    func sendHangup(callId: String, targetUserId: String) {
        emit("call:hangup", ["callId": callId, "targetUserId": targetUserId])
    }

    func sendDecline(callId: String, targetUserId: String) {
        emit("call:decline", ["callId": callId, "targetUserId": targetUserId])
    }

    // MARK: - Chat Emit

    /// Sends a message with Socket.IO ack. completion(true) = server confirmed.
    func sendMessage(
        chatId: String,
        content: String,
        replyToId: String? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard isConnected else { completion?(false); return }
        var payload: [String: Any] = ["chatId": chatId, "content": content]
        if let replyToId { payload["replyToId"] = replyToId }

        socket?.emitWithAck("message:send", payload).timingOut(after: 5) { data in
            let ok = (data.first as? [String: Any])?["ok"] as? Bool ?? false
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    func sendRead(chatId: String, messageId: String) {
        emit("message:read", ["chatId": chatId, "messageId": messageId])
    }

    func sendTypingStart(chatId: String) {
        emit("typing:start", ["chatId": chatId])
    }

    func sendTypingStop(chatId: String) {
        emit("typing:stop", ["chatId": chatId])
    }

    // MARK: - Private

    private func emit(_ event: String, _ payload: [String: Any]) {
        guard isConnected else { return }
        socket?.emit(event, payload)
    }

    private func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? Self.decoder.decode(type, from: data)
    }

    private func setupHandlers() {
        guard let socket else { return }

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.isConnected = true }
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.isConnected = false }
        }

        // MARK: Call events

        // call:incoming → { callId, fromUserId, type, sdp }
        socket.on("call:incoming") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let fromUserId = dict["fromUserId"] as? String,
                  let typeStr = dict["type"] as? String,
                  let type = CallType(rawValue: typeStr),
                  let sdp = dict["sdp"] as? String else { return }
            let event = IncomingCallEvent(callId: callId, initiatorId: fromUserId, type: type, sdp: sdp)
            DispatchQueue.main.async { self?.incomingCall = event }
        }

        // call:answered → { callId, sdp }
        socket.on("call:answered") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let sdp = dict["sdp"] as? String else { return }
            let event = CallAnsweredEvent(callId: callId, sdp: sdp)
            DispatchQueue.main.async { self?.answeredCall = event }
        }

        // call:ice-candidate → { callId, fromUserId, candidate: { candidate, sdpMid, ... } }
        socket.on("call:ice-candidate") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let fromUserId = dict["fromUserId"] as? String,
                  let cd = dict["candidate"] as? [String: Any],
                  let candidateStr = cd["candidate"] as? String else { return }
            let event = IceCandidateEvent(
                callId: callId, fromUserId: fromUserId, candidate: candidateStr,
                sdpMid: cd["sdpMid"] as? String,
                sdpMLineIndex: cd["sdpMLineIndex"] as? Int,
                usernameFragment: cd["usernameFragment"] as? String
            )
            DispatchQueue.main.async { self?.iceCandidate = event }
        }

        // call:hangup → { callId }
        socket.on("call:hangup") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }
            let event = CallHangupEvent(callId: callId)
            DispatchQueue.main.async { self?.remoteHangup = event }
        }

        // call:declined → { callId }
        socket.on("call:declined") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }
            let event = CallHangupEvent(callId: callId)
            DispatchQueue.main.async { self?.remoteDeclined = event }
        }

        // MARK: Chat events

        // message:new — full Message object (sent to all members except sender)
        socket.on("message:new") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let message = self.decode(Message.self, from: dict) else { return }
            let event = NewMessageEvent(message: message)
            DispatchQueue.main.async { self.newMessage = event }
        }

        // message:ack → { messageId, chatId }
        socket.on("message:ack") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let messageId = dict["messageId"] as? String,
                  let chatId = dict["chatId"] as? String else { return }
            let event = MessageAckEvent(messageId: messageId, chatId: chatId)
            DispatchQueue.main.async { self?.messageAck = event }
        }

        // message:read → { chatId, messageId, userId, readAt }
        socket.on("message:read") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let chatId = dict["chatId"] as? String,
                  let messageId = dict["messageId"] as? String,
                  let userId = dict["userId"] as? String,
                  let readAtStr = dict["readAt"] as? String else { return }
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let readAt = fmt.date(from: readAtStr) ?? Date()
            let event = MessageReadEvent(chatId: chatId, messageId: messageId, userId: userId, readAt: readAt)
            DispatchQueue.main.async { self?.messageRead = event }
        }

        // typing:start → { chatId, userId }
        socket.on("typing:start") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let chatId = dict["chatId"] as? String,
                  let userId = dict["userId"] as? String else { return }
            let event = TypingEvent(chatId: chatId, userId: userId)
            DispatchQueue.main.async { self?.typingStart = event }
        }

        // typing:stop → { chatId, userId }
        socket.on("typing:stop") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let chatId = dict["chatId"] as? String,
                  let userId = dict["userId"] as? String else { return }
            let event = TypingEvent(chatId: chatId, userId: userId)
            DispatchQueue.main.async { self?.typingStop = event }
        }
    }
}
