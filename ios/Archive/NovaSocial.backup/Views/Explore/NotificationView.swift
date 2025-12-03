import SwiftUI

struct NotificationView: View {
    @StateObject private var viewModel = NotificationViewModel()
    @State private var selectedPost: Post?
    @State private var selectedUser: User?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    LoadingView(message: "Loading notifications...")
                } else if viewModel.notifications.isEmpty {
                    EmptyStateView(
                        icon: "bell.slash",
                        title: "No Notifications",
                        message: "Your notifications will appear here"
                    )
                } else {
                    List(viewModel.notifications) { notification in
                        NotificationCell(notification: notification)
                            .onTapGesture {
                                handleNotificationTap(notification)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !notification.isRead {
                                    Button {
                                        viewModel.markAsRead(notification: notification)
                                    } label: {
                                        Label("Mark Read", systemImage: "checkmark")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.unreadCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Mark All Read") {
                            viewModel.markAllAsRead()
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationDestination(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .navigationDestination(item: $selectedUser) { user in
                UserProfileView(userId: user.id)
            }
            .task {
                if viewModel.notifications.isEmpty {
                    await viewModel.loadNotifications()
                }
            }
            .refreshable {
                await viewModel.refreshNotifications()
            }
            .errorAlert(
                isPresented: $viewModel.showError,
                message: viewModel.errorMessage
            )
        }
    }

    private func handleNotificationTap(_ notification: Notification) {
        viewModel.markAsRead(notification: notification)

        switch notification.type {
        case .like, .comment:
            if let post = notification.post {
                selectedPost = post
            }
        case .follow:
            if let actor = notification.actor {
                selectedUser = actor
            }
        case .mention:
            if let post = notification.post {
                selectedPost = post
            }
        }
    }
}

struct NotificationCell: View {
    let notification: Notification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Actor Avatar
            AsyncImageView(url: notification.actor?.avatarUrl)
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(notificationText)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Text(notification.createdAt.timeAgoDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Post Thumbnail (if applicable)
            if let post = notification.post {
                AsyncImageView(url: post.thumbnailUrl ?? post.imageUrl)
                    .frame(width: 44, height: 44)
                    .cornerRadius(4)
            }

            // Unread Indicator
            if !notification.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }

    private var notificationText: AttributedString {
        let username = notification.actor?.username ?? "Someone"

        switch notification.type {
        case .like:
            return AttributedString("\(username) liked your post")
        case .comment:
            return AttributedString("\(username) commented on your post")
        case .follow:
            return AttributedString("\(username) started following you")
        case .mention:
            return AttributedString("\(username) mentioned you in a post")
        }
    }
}

#Preview {
    NotificationView()
}
