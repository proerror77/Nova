import SwiftUI

struct ConversationListView: View {
    @State private var conversations: [UUID] = []
    @State private var inputConversation = ""
    @State private var peerId = ""
    @State private var showDetail: UUID?
    @State private var alert: String?

    private let repo = MessagingRepository()

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Conversation UUID", text: $inputConversation)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if let id = UUID(uuidString: inputConversation) {
                            conversations.append(id)
                            showDetail = id
                            inputConversation = ""
                        } else {
                            alert = "請輸入有效的 Conversation UUID"
                        }
                    }
                }
                HStack {
                    TextField("Peer User UUID", text: $peerId)
                        .textFieldStyle(.roundedBorder)
                    Button("Create 1:1") {
                        Task { await createDirect() }
                    }
                }

                List(conversations, id: \.self) { id in
                    NavigationLink(destination: ConversationDetailView(conversationId: id), tag: id, selection: $showDetail) {
                        VStack(alignment: .leading) {
                            Text(id.uuidString).font(.footnote.monospaced())
                            Text("Tap to open").foregroundColor(.secondary).font(.caption2)
                        }
                    }
                }
                .listStyle(.plain)

                Spacer()
            }
            .padding()
            .navigationTitle("Messages")
            .alert(item: Binding(get: {
                alert.map { AlertWrapper(message: $0) }
            }, set: { _ in alert = nil })) { wrapper in
                Alert(title: Text(wrapper.message))
            }
        }
    }

    private func createDirect() async {
        guard let meId = UUIDMapper.userStringToUUID(AuthManager.shared.currentUser?.id) else {
            alert = "目前使用者 ID 不是有效 UUID（且未啟用本地映射）"
            return
        }
        guard let peer = UUIDMapper.userStringToUUID(peerId) else { alert = "對方使用者 ID 非 UUID，且本地映射未啟用或輸入為空"; return }
        do {
            let resp = try await repo.createDirectConversation(userA: meId, userB: peer)
            conversations.append(resp.id)
            showDetail = resp.id
            peerId = ""
        } catch {
            alert = "建立會話失敗：\\(error.localizedDescription)"
        }
    }
}

private struct AlertWrapper: Identifiable { let id = UUID(); let message: String }
