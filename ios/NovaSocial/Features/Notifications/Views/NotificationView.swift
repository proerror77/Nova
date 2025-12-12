import SwiftUI

struct NotificationView: View {
    @Binding var showNotification: Bool
    @StateObject private var viewModel = NotificationViewModel()
    @State private var showChat = false
    @State private var selectedUserName = ""
    @State private var selectedConversationId = ""

    var body: some View {
        ZStack {
            if showChat {
                ChatView(showChat: $showChat, conversationId: selectedConversationId, userName: selectedUserName)
                    .transition(.identity)
            } else {
                notificationContent
            }
        }
        .animation(.none, value: showChat)
        .task {
            await viewModel.loadNotifications()
        }
    }

    private var notificationContent: some View {
        ZStack {
            // MARK: - Background
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Navigation Bar
                HStack {
                    Button(action: {
                        showNotification = false
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    Text("Notification")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(DesignTokens.surface)

                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.borderColor)

                // MARK: - Content
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = viewModel.error, viewModel.notifications.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(DesignTokens.textSecondary)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await viewModel.loadNotifications()
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                    .padding()
                    Spacer()
                } else if viewModel.notifications.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40))
                            .foregroundColor(DesignTokens.textSecondary)
                        Text("No notifications yet")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                    Spacer()
                } else {
                    // MARK: - Notification List
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // Today Section
                            if !viewModel.todayNotifications.isEmpty {
                                NotificationSection(
                                    title: "Today",
                                    notifications: viewModel.todayNotifications,
                                    viewModel: viewModel,
                                    onMessageTap: { notification in
                                        selectedUserName = notification.userName ?? "User"
                                        selectedConversationId = "notification_conv_\(notification.relatedUserId ?? notification.id)"
                                        showChat = true
                                    }
                                )
                            }

                            // Last 7 Days Section
                            if !viewModel.lastSevenDaysNotifications.isEmpty {
                                NotificationSection(
                                    title: "Last 7 Days",
                                    notifications: viewModel.lastSevenDaysNotifications,
                                    viewModel: viewModel,
                                    onMessageTap: { notification in
                                        selectedUserName = notification.userName ?? "User"
                                        selectedConversationId = "notification_conv_\(notification.relatedUserId ?? notification.id)"
                                        showChat = true
                                    }
                                )
                            }

                            // Last 30 Days Section
                            if !viewModel.lastThirtyDaysNotifications.isEmpty {
                                NotificationSection(
                                    title: "Last 30 Days",
                                    notifications: viewModel.lastThirtyDaysNotifications,
                                    viewModel: viewModel,
                                    onMessageTap: { notification in
                                        selectedUserName = notification.userName ?? "User"
                                        selectedConversationId = "notification_conv_\(notification.relatedUserId ?? notification.id)"
                                        showChat = true
                                    }
                                )
                            }

                            // Older Section
                            if !viewModel.olderNotifications.isEmpty {
                                NotificationSection(
                                    title: "Older",
                                    notifications: viewModel.olderNotifications,
                                    viewModel: viewModel,
                                    onMessageTap: { notification in
                                        selectedUserName = notification.userName ?? "User"
                                        selectedConversationId = "notification_conv_\(notification.relatedUserId ?? notification.id)"
                                        showChat = true
                                    }
                                )
                            }

                            // Load More
                            if viewModel.hasMore {
                                HStack {
                                    Spacer()
                                    if viewModel.isLoadingMore {
                                        ProgressView()
                                    } else {
                                        Button("Load More") {
                                            Task {
                                                await viewModel.loadMore()
                                            }
                                        }
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
        }
    }
}

// MARK: - Notification List Item Component
// MARK: - Notification Section Component

struct NotificationSection: View {
    let title: String
    let notifications: [NotificationItem]
    let viewModel: NotificationViewModel
    var onMessageTap: ((NotificationItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(.horizontal, 16)

            ForEach(notifications) { notification in
                NotificationListItem(
                    notification: notification,
                    viewModel: viewModel,
                    onMessageTap: {
                        onMessageTap?(notification)
                    }
                )
            }
        }
    }
}

struct NotificationListItem: View {
    let notification: NotificationItem
    let viewModel: NotificationViewModel
    var onMessageTap: (() -> Void)?
    @State private var isFollowing = false
    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 13) {
            // Avatar - 42x42
            if let avatarUrl = notification.userAvatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                            .frame(width: 42, height: 42)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                    case .failure:
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                            .frame(width: 42, height: 42)
                    @unknown default:
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                            .frame(width: 42, height: 42)
                    }
                }
            } else {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 42, height: 42)
            }

            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(notification.userName ?? "User")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DesignTokens.textPrimary)

                HStack(spacing: 4) {
                    Text(notification.actionText)
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(notification.relativeTimeString)
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                }
            }

            Spacer()

            // Button based on notification type
            switch notification.buttonType {
            case .message:
                Button(action: {
                    onMessageTap?()
                }) {
                    Text("Message")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)
                }
                .frame(width: 85, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .inset(by: 0.50)
                        .stroke(DesignTokens.textPrimary, lineWidth: 0.50)
                )

            case .follow, .followBack:
                Button(action: {
                    guard !isProcessing, let userId = notification.relatedUserId else { return }
                    isProcessing = true
                    Task {
                        if isFollowing {
                            let success = await viewModel.unfollowUser(userId: userId)
                            if success {
                                isFollowing = false
                            }
                        } else {
                            let success = await viewModel.followUser(userId: userId)
                            if success {
                                isFollowing = true
                            }
                        }
                        isProcessing = false
                    }
                }) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(isFollowing ? "Following" : (notification.buttonType == .followBack ? "Follow back" : "Follow"))
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                }
                .frame(width: 85, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .inset(by: 0.50)
                        .stroke(Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.50)
                )
                .disabled(isProcessing)

            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DesignTokens.surface)
    }
}

#Preview {
    NotificationView(showNotification: .constant(true))
}
