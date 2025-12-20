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

                    // Mark all as read button
                    if viewModel.unreadCount > 0 {
                        Button(action: {
                            Task {
                                await viewModel.markAllAsRead()
                            }
                        }) {
                            Image(systemName: "checkmark.circle")
                                .frame(width: 24, height: 24)
                                .foregroundColor(DesignTokens.textPrimary)
                        }
                    } else {
                        Color.clear
                            .frame(width: 24)
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(DesignTokens.surface)

                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.borderColor)

                // MARK: - Content
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    loadingView
                } else if let error = viewModel.error, viewModel.notifications.isEmpty {
                    errorView(error)
                } else if viewModel.notifications.isEmpty {
                    emptyView
                } else {
                    notificationList
                }
            }
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading notifications...")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textSecondary)
                .padding(.top, 12)
            Spacer()
        }
    }

    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(DesignTokens.textSecondary)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: {
                Task {
                    await viewModel.loadNotifications()
                }
            }) {
                Text("Retry")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .cornerRadius(20)
            }
            Spacer()
        }
    }

    // MARK: - Empty View
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(DesignTokens.textSecondary)
            Text("No notifications yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignTokens.textPrimary)
            Text("When you get notifications, they'll show up here")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Notification List
    private var notificationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                // Today Section
                if !viewModel.todayNotifications.isEmpty {
                    notificationSection(title: "Today", notifications: viewModel.todayNotifications)
                }

                // Last 7 Days Section
                if !viewModel.lastSevenDaysNotifications.isEmpty {
                    notificationSection(title: "Last 7 Days", notifications: viewModel.lastSevenDaysNotifications)
                }

                // Last 30 Days Section
                if !viewModel.lastThirtyDaysNotifications.isEmpty {
                    notificationSection(title: "Last 30 Days", notifications: viewModel.lastThirtyDaysNotifications)
                }

                // Older Section
                if !viewModel.olderNotifications.isEmpty {
                    notificationSection(title: "Earlier", notifications: viewModel.olderNotifications)
                }

                // Load More Indicator
                if viewModel.hasMore {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        } else {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task {
                                        await viewModel.loadMore()
                                    }
                                }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Notification Section
    private func notificationSection(title: String, notifications: [NotificationItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(.horizontal, 16)

            ForEach(notifications) { notification in
                NotificationListItem(
                    notification: notification,
                    onMessageTap: {
                        guard let userId = notification.relatedUserId else { return }
                        selectedUserName = notification.userName ?? "User"
                        Task {
                            do {
                                if !MatrixBridgeService.shared.isInitialized {
                                    try await MatrixBridgeService.shared.initialize()
                                }
                                let room = try await MatrixBridgeService.shared.createDirectConversation(
                                    withUserId: userId,
                                    displayName: selectedUserName
                                )
                                await MainActor.run {
                                    selectedConversationId = room.id
                                    showChat = true
                                }
                            } catch {
                                #if DEBUG
                                print("[NotificationView] Failed to start chat: \(error)")
                                #endif
                            }
                        }
                    },
                    onFollowTap: { isFollowing in
                        Task {
                            if let userId = notification.relatedUserId {
                                if isFollowing {
                                    _ = await viewModel.unfollowUser(userId: userId)
                                } else {
                                    _ = await viewModel.followUser(userId: userId)
                                }
                            }
                        }
                    },
                    onAppear: {
                        if !notification.isRead {
                            Task {
                                await viewModel.markAsRead(notificationId: notification.id)
                            }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Notification List Item Component

struct NotificationListItem: View {
    let notification: NotificationItem
    var onMessageTap: (() -> Void)?
    var onFollowTap: ((Bool) -> Void)?
    var onAppear: (() -> Void)?

    @State private var isFollowing = false

    var body: some View {
        HStack(spacing: 13) {
            // Avatar - 42x42
            AvatarView(
                image: nil,
                url: notification.userAvatarUrl,
                size: 42,
                backgroundColor: Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
            )

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

            // Unread indicator
            if !notification.isRead {
                Circle()
                    .fill(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .frame(width: 8, height: 8)
            }

            // Action Button
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(notification.isRead ? DesignTokens.surface : DesignTokens.surface.opacity(0.95))
        .onAppear {
            onAppear?()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
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

        case .follow:
            Button(action: {
                isFollowing.toggle()
                onFollowTap?(isFollowing)
            }) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 12))
                    .foregroundColor(isFollowing ? DesignTokens.textSecondary : Color(red: 0.87, green: 0.11, blue: 0.26))
            }
            .frame(width: 85, height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .inset(by: 0.50)
                    .stroke(isFollowing ? DesignTokens.textSecondary : Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.50)
            )

        case .followBack:
            Button(action: {
                isFollowing.toggle()
                onFollowTap?(isFollowing)
            }) {
                Text(isFollowing ? "Following" : "Follow back")
                    .font(.system(size: 12))
                    .foregroundColor(isFollowing ? DesignTokens.textSecondary : Color(red: 0.87, green: 0.11, blue: 0.26))
            }
            .frame(width: 85, height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .inset(by: 0.50)
                    .stroke(isFollowing ? DesignTokens.textSecondary : Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.50)
            )

        case .none:
            EmptyView()
        }
    }
}

#Preview {
    NotificationView(showNotification: .constant(true))
}
