import SwiftUI

// MARK: - View Stubs
// Placeholder views for features that are temporarily disabled
// Note: MessageView, ChatView, NewChatView are now in Features/Chat/Views/

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
