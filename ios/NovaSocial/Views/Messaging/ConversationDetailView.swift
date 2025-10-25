import SwiftUI

struct ConversationDetailView: View {
    let conversationId: UUID
    @StateObject private var vm = MessagingViewModel()
    @State private var text = ""
    @State private var typingTs: Date = .distantPast

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.messages, id: \.id) { m in
                            HStack(alignment: .top, spacing: 8) {
                                Text("#\\(m.sequenceNumber)").font(.caption2).foregroundColor(.secondary)
                                VStack(alignment: .leading) {
                                    Text(m.senderId.uuidString).font(.caption2).foregroundColor(.secondary)
                                    Text("(encrypted)").font(.footnote)
                                }
                            }
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

            HStack {
                TextField("Type a message", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { _ in
                        throttleTyping()
                    }
                Button("Send") {
                    Task { await vm.sendMessage(text); text = "" }
                }.disabled(text.isEmpty)
            }.padding(.horizontal)
        }
        .navigationTitle("Conversation")
        .task { await setup() }
        .onDisappear { vm.disconnect() }
    }

    private func setup() async {
        let uid = UUIDMapper.userStringToUUID(AuthManager.shared.currentUser?.id)
        guard let uid else { return }
        await vm.load(conversationId: conversationId)
        vm.connect(conversationId: conversationId, userId: uid)
    }

    private func throttleTyping() {
        let now = Date()
        if now.timeIntervalSince(typingTs) > 1.0 {
            vm.sendTyping()
            typingTs = now
        }
    }
}
