import SwiftUI

struct ChatView: View {
    @State private var vm: ChatViewModel

    init(conversationId: UUID, peerUserId: UUID) {
        _vm = State(initialValue: ChatViewModel(conversationId: conversationId, peerUserId: peerUserId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // === 消息列表 ===
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { m in
                            MessageBubble(message: m)
                                .id(m.id)
                        }

                        // 輸入中指示器
                        if !vm.typingUsernames.isEmpty {
                            HStack(spacing: 4) {
                                Text("對方正在輸入")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ProgressView()
                                    .scaleEffect(0.7, anchor: .center)
                            }
                            .padding(.leading, 16)
                            .padding(.top, 8)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: vm.messages.count) { _ in
                    // 自動滾動到最新消息
                    if let lastMessage = vm.messages.last {
                        withAnimation {
                            scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // === 狀態指示器 ===
            StatusBar(vm: vm)

            // === 輸入框 ===
            MessageInputField(vm: vm)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ConnectionStatusIcon(isConnected: vm.isConnected)
            }
        }
        .task { await vm.start() }
        .alert(item: Binding(get: {
            vm.error.map { LocalizedErrorWrapper(message: $0) }
        }, set: { _ in vm.error = nil })) { wrapper in
            Alert(title: Text("錯誤"), message: Text(wrapper.message), dismissButton: .default(Text("確定")))
        }
    }
}

// MARK: - Message Bubble Component

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.mine { Spacer(minLength: 32) }

            VStack(alignment: message.mine ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.mine ? Color.blue.opacity(0.85) : Color.gray.opacity(0.15))
                    .foregroundColor(message.mine ? .white : .primary)
                    .cornerRadius(12)

                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }

            if !message.mine { Spacer(minLength: 32) }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Bar Component

private struct StatusBar: View {
    let vm: ChatViewModel

    var body: some View {
        if vm.offlineMessageCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("有 \(vm.offlineMessageCount) 條消息待發送")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("網路恢復時將自動發送")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                ProgressView()
                    .scaleEffect(0.8, anchor: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }
}

// MARK: - Message Input Field Component

private struct MessageInputField: View {
    @Bindable var vm: ChatViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("輸入消息…", text: $vm.input)
                .onChange(of: vm.input) { _ in vm.typing() }
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .submitLabel(.send)

            Button(action: {
                Task { await vm.send() }
                isFocused = false
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Connection Status Icon

private struct ConnectionStatusIcon: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(isConnected ? "已連接" : "未連接")
                .font(.caption2)
                .foregroundColor(isConnected ? .green : .gray)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Helper Types

private struct LocalizedErrorWrapper: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView(conversationId: UUID(), peerUserId: UUID())
    }
}
