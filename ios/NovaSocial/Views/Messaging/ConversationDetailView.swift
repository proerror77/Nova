import SwiftUI
import AVFoundation

struct ConversationDetailView: View {
    let conversationId: UUID
    @StateObject private var vm = MessagingViewModel()
    @State private var voiceMessageService = VoiceMessageService()
    @State private var text = ""
    @State private var typingTs: Date = .distantPast
    @State private var isSendingVoiceMessage = false
    @State private var voiceMessageError: String?

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.messages, id: \.id) { m in
                            messageRow(for: m)
                                .id(m.id)
                        }
                        if !vm.typingUsers.isEmpty {
                            Text("typing...").italic().foregroundColor(.secondary)
                        }
                    }.padding(.horizontal)
                }
                .onChange(of: vm.messages.count) { _ in
                    if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            // Error message display
            if let error = voiceMessageError {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button(action: { voiceMessageError = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Message composer with WeChat-style voice message support
            MessageComposerView(
                text: $text,
                onSend: {
                    Task { await vm.sendMessage(text); text = "" }
                },
                onSendVoiceMessage: { audioURL in
                    Task { await sendVoiceMessage(audioURL) }
                }
            )
            .disabled(isSendingVoiceMessage)
        }
        .navigationTitle("Conversation")
        .task { await setup() }
        .onDisappear { vm.disconnect() }
    }

    @ViewBuilder
    private func messageRow(for message: Message) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("#\\(message.sequenceNumber)")
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.senderId.uuidString)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Display different message types
                if let messageType = message.messageType, messageType == "audio" {
                    // Voice message
                    if let audioURL = URL(string: message.content) {
                        VoiceMessagePlayerView(
                            audioURL: audioURL,
                            senderName: message.senderName,
                            timestamp: message.createdAt
                        )
                    }
                } else {
                    // Text message
                    Text(message.content)
                        .lineLimit(nil)
                    Text("(encrypted)")
                        .font(.footnote)
                }
            }
        }
    }

    private func setup() async {
        let uid = UUIDMapper.userStringToUUID(AuthManager.shared.currentUser?.id)
        guard let uid else { return }
        await vm.load(conversationId: conversationId)
        vm.connect(conversationId: conversationId, userId: uid)
    }

    private func sendVoiceMessage(_ audioURL: URL) async {
        isSendingVoiceMessage = true
        voiceMessageError = nil

        do {
            // Get audio duration
            let audioData = try Data(contentsOf: audioURL)
            let audioAsset = AVAsset(url: audioURL)
            let duration = await audioAsset.load(.duration).seconds

            // Send voice message
            let response = try await voiceMessageService.sendVoiceMessage(
                conversationId: conversationId.uuidString,
                audioURL: audioURL,
                duration: duration
            )

            // Reload messages to show the sent voice message
            await vm.load(conversationId: conversationId)

            isSendingVoiceMessage = false
        } catch {
            voiceMessageError = "Failed to send voice message: \(error.localizedDescription)"
            isSendingVoiceMessage = false
        }
    }

    private func throttleTyping() {
        let now = Date()
        if now.timeIntervalSince(typingTs) > 1.0 {
            vm.sendTyping()
            typingTs = now
        }
    }
}
