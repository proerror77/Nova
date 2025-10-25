import SwiftUI

struct ChatView: View {
    @State private var vm: ChatViewModel

    init(conversationId: UUID, peerUserId: UUID) {
        _vm = State(initialValue: ChatViewModel(conversationId: conversationId, peerUserId: peerUserId))
    }

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.messages) { m in
                        HStack {
                            if m.mine { Spacer() }
                            Text(m.text)
                                .padding(10)
                                .background(m.mine ? Color.blue.opacity(0.85) : Color.gray.opacity(0.2))
                                .foregroundColor(m.mine ? .white : .primary)
                                .cornerRadius(10)
                            if !m.mine { Spacer() }
                        }
                    }
                    if !vm.typingUsernames.isEmpty {
                        Text("typing…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }.padding()
            }
            HStack {
                TextField("Message", text: $vm.input)
                    .onChange(of: vm.input) { _ in vm.typing() }
                    .textFieldStyle(.roundedBorder)
                Button("Send") { Task { await vm.send() } }
            }.padding()
        }
        .navigationTitle("Chat")
        .task { await vm.start() }
        .alert(item: Binding(get: {
            vm.error.map { LocalizedErrorWrapper(message: $0) }
        }, set: { _ in vm.error = nil })) { wrapper in
            Alert(title: Text("Error"), message: Text(wrapper.message), dismissButton: .default(Text("OK")))
        }
    }
}

private struct LocalizedErrorWrapper: Identifiable {
    let id = UUID()
    let message: String
}
