import SwiftUI

struct StartChatSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var peerIdText: String = ""
    let onStart: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Peer User ID (UUID)") {
                    TextField("00000000-0000-0000-0000-000000000000", text: $peerIdText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                }
                Section {
                    Button("Start Chat") {
                        guard let peer = UUID(uuidString: peerIdText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                        onStart(peer)
                    }
                    .disabled(UUID(uuidString: peerIdText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                }
            }
            .navigationTitle("New Chat")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
