import SwiftUI

// MARK: - View Stubs
// Placeholder views for features that are temporarily disabled
// Note: MessageView, ChatView, NewChatView, and ChatService are now implemented
// in Features/Chat/ and Shared/Services/Chat/

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
