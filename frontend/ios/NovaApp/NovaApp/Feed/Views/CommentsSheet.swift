import SwiftUI

/// C01 - Comments Bottom Sheet (template)
struct CommentsSheet: View {
    let postId: String

    var body: some View {
        NavigationStack {
            Text("Comments for post: \(postId)")
                .navigationTitle("Comments")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
