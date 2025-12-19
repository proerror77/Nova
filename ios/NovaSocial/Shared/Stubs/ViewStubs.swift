import SwiftUI

// MARK: - View Stubs
// Placeholder views for features that are temporarily disabled

struct MessageView: View {
    @Binding var currentPage: AppPage

    init(currentPage: Binding<AppPage>) {
        self._currentPage = currentPage
    }

    var body: some View {
        VStack {
            Image(systemName: "message.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("Messages Coming Soon")
                .foregroundColor(.gray)
        }
        .navigationTitle("Messages")
    }
}

struct AddFriendsView: View {
    @Binding var currentPage: AppPage

    init(currentPage: Binding<AppPage>) {
        self._currentPage = currentPage
    }

    var body: some View {
        VStack {
            Image(systemName: "person.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("Add Friends Coming Soon")
                .foregroundColor(.gray)
        }
        .navigationTitle("Add Friends")
    }
}

struct NewChatView: View {
    @Binding var currentPage: AppPage

    init(currentPage: Binding<AppPage>) {
        self._currentPage = currentPage
    }

    var body: some View {
        VStack {
            Image(systemName: "plus.message.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("New Chat Coming Soon")
                .foregroundColor(.gray)
        }
        .navigationTitle("New Chat")
    }
}

struct StartGroupChatView: View {
    var body: some View {
        VStack {
            Image(systemName: "person.3.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("Group Chat Coming Soon")
                .foregroundColor(.gray)
        }
        .navigationTitle("Start Group Chat")
    }
}

struct ChatView: View {
    @Binding var showChat: Bool
    let conversationId: String
    let userName: String

    init(showChat: Binding<Bool> = .constant(false), conversationId: String = "", userName: String = "") {
        self._showChat = showChat
        self.conversationId = conversationId
        self.userName = userName
    }

    var body: some View {
        VStack {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("Chat Coming Soon")
                .foregroundColor(.gray)
        }
        .navigationTitle("Chat")
    }
}

struct ChatService {
    static let shared = ChatService()
    private init() {}

    var isEnabled: Bool { false }
}
