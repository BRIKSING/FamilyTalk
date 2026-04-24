//
//  CallView.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import SwiftUI

struct CallView: View {
    @Bindable var viewModel: CallViewModel
    let targetUser: User
    let callType: CallType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay {
                        Text(targetUser.displayName.prefix(1).uppercased())
                            .font(.system(size: 50))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    .shadow(radius: 20)

                Text(targetUser.displayName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Image(systemName: callType == .voice ? "phone.fill" : "video.fill")
                    Text(callType == .voice ? "Голосовой звонок" : "Видеозвонок")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

                Text(callStatusText)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))

                if case .connected = viewModel.callState {
                    Text(viewModel.callDurationText)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                Spacer()

                callControls
                    .padding(.bottom, 60)
            }
            .padding()
        }
        .onAppear {
            if viewModel.callState == .idle {
                viewModel.startCall(to: targetUser, type: callType)
            }
        }
        .onChange(of: viewModel.callState) { _, newState in
            if case .ended = newState {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    viewModel.reset()
                    dismiss()
                }
            } else if case .failed = newState {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    viewModel.reset()
                    dismiss()
                }
            }
        }
        // Socket events — observe and forward to ViewModel
        .onChange(of: SocketService.shared.answeredCall) { _, event in
            guard let event else { return }
            viewModel.handleCallAnswered(event)
            SocketService.shared.answeredCall = nil
        }
        .onChange(of: SocketService.shared.remoteHangup) { _, event in
            guard event != nil else { return }
            viewModel.handleRemoteEnded()
            SocketService.shared.remoteHangup = nil
        }
        .onChange(of: SocketService.shared.remoteDeclined) { _, event in
            guard event != nil else { return }
            viewModel.handleRemoteEnded()
            SocketService.shared.remoteDeclined = nil
        }
    }

    private var callStatusText: String {
        switch viewModel.callState {
        case .idle:       return "Подготовка..."
        case .initiating: return "Инициализация..."
        case .ringing:    return "Звоним..."
        case .connected:  return "Соединение установлено"
        case .ended:      return "Звонок завершён"
        case .failed(let error): return "Ошибка: \(error)"
        }
    }

    @ViewBuilder
    private var callControls: some View {
        HStack(spacing: 60) {
            Button(action: {}) {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "mic.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
            }

            Button(action: { viewModel.endCall() }) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Image(systemName: "phone.down.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .shadow(radius: 10)
            }

            Button(action: {}) {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}

#Preview {
    CallView(
        viewModel: CallViewModel(),
        targetUser: User(
            id: "1",
            displayName: "Иван Иванов",
            username: "john_doe",
            bio: "Семейный чат",
            lastSeen: Date()
        ),
        callType: .voice
    )
}
