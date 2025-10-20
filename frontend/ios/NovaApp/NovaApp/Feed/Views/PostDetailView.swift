import SwiftUI

/// P01 - Post Detail Screen (template)
struct PostDetailView: View {
    let postId: String
    @StateObject private var viewModel = PostDetailViewModel()

    var body: some View {
        Text("Post Detail: \(postId)")
            .font(Theme.Typography.h3)
            .onAppear {
                Task { await viewModel.loadPost(postId: postId) }
            }
    }
}

@MainActor
class PostDetailViewModel: ObservableObject {
    @Published var post: Post?

    func loadPost(postId: String) async {
        // TODO: Fetch post from repository
    }
}
