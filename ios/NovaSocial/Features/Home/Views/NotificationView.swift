import SwiftUI

struct NotificationView: View {
    @Binding var showNotification: Bool
    @State private var viewModel = NotificationViewModel()
    @State private var showChat = false
    @State private var selectedUserName = ""
    @State private var selectedConversationId = ""
    @State private var showPostDetail = false
    @State private var selectedPostId: String?
    @State private var showUserProfile = false
    @State private var selectedUserId: String?

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
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
                    .onDisappear {
                        selectedUserId = nil
                    }
            }
        }
        .alert("Feature Coming Soon", isPresented: $showPostDetail) {
            Button("OK", role: .cancel) {
                showPostDetail = false
                selectedPostId = nil
            }
        } message: {
            Text("Post detail view will be available soon. Post ID: \(selectedPostId ?? "unknown")")
        }
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
                        .font(Font.custom("SFProDisplay-Medium", size: 24.f))
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    NotificationRowSkeleton()
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48.f))
                .foregroundColor(DesignTokens.textSecondary)
            Text(message)
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: {
                Task {
                    await viewModel.loadNotifications()
                }
            }) {
                Text("Retry")
                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
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
                .font(.system(size: 48.f))
                .foregroundColor(DesignTokens.textSecondary)
            Text("No notifications yet")
                .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                .foregroundColor(DesignTokens.textPrimary)
            Text("When you get notifications, they'll show up here")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
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
                .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(.horizontal, 16)

            ForEach(notifications) { notification in
                NotificationListItem(
                    notification: notification,
                    onTap: {
                        // Navigate based on notification type
                        switch notification.type {
                        case .like, .comment, .share:
                            // Navigate to post detail
                            if let postId = notification.relatedPostId {
                                selectedPostId = postId
                                showPostDetail = true
                            }
                        case .reply:
                            // Navigate to post detail (comment is in the post)
                            if let postId = notification.relatedPostId {
                                selectedPostId = postId
                                showPostDetail = true
                            }
                        case .follow, .friendRequest, .friendAccepted:
                            // Navigate to user profile
                            if let userId = notification.relatedUserId {
                                selectedUserId = userId
                                showUserProfile = true
                            }
                        case .mention:
                            // Navigate to post where mentioned
                            if let postId = notification.relatedPostId {
                                selectedPostId = postId
                                showPostDetail = true
                            }
                        case .system:
                            // System notifications don't navigate
                            break
                        }
                    },
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
    var onTap: (() -> Void)?
    var onMessageTap: (() -> Void)?
    var onFollowTap: ((Bool) -> Void)?
    var onAppear: (() -> Void)?

    @State private var isFollowing = false
    @State private var isLoadingFollowStatus = false

    private let graphService = GraphService()
    private var currentUserId: String? {
        KeychainService.shared.get(.userId)
    }

    var body: some View {
        HStack(spacing: 13) {
            // Avatar - 42x42
            AvatarView(
                image: nil,
                url: notification.userAvatarUrl,
                size: 42,
                name: notification.userName,
                backgroundColor: Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
            )

            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(notification.userName ?? "User")
                    .font(Font.custom("SFProDisplay-Bold", size: 16.f))
                    .foregroundColor(DesignTokens.textPrimary)

                HStack(spacing: 4) {
                    Text(notification.actionText)
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(notification.relativeTimeString)
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
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
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            onAppear?()

            // Load follow status for follow-related notifications
            if notification.buttonType == .follow || notification.buttonType == .followBack {
                Task {
                    await loadFollowStatus()
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func loadFollowStatus() async {
        guard let currentUserId = currentUserId,
              let targetUserId = notification.relatedUserId,
              !isLoadingFollowStatus else {
            return
        }

        isLoadingFollowStatus = true

        do {
            let following = try await graphService.isFollowing(
                followerId: currentUserId,
                followeeId: targetUserId
            )

            await MainActor.run {
                self.isFollowing = following
                self.isLoadingFollowStatus = false
            }
        } catch {
            #if DEBUG
            print("[NotificationListItem] Failed to load follow status: \(error)")
            #endif

            await MainActor.run {
                self.isLoadingFollowStatus = false
            }
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
                    .font(Font.custom("SFProDisplay-Medium", size: 12.f))
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
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
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
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
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
