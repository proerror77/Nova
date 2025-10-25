import SwiftUI

struct MessageComposerView: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack {
            TextField("Type a message", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSend)
            Button("Send", action: onSend).disabled(text.isEmpty)
        }
    }
}

