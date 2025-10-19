import SwiftUI

// MARK: - Complete Example: User List with All Features

/// Complete example showing how to use all components together
struct ExampleUsageView: View {
    @StateObject private var viewModel = UserListViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom header
                NovaSectionHeader(
                    title: "用户列表",
                    actionTitle: "查看全部",
                    action: {
                        print("View all tapped")
                    }
                )

                // Stateful list with all features
                NovaStatefulList(
                    state: viewModel.state,
                    isLoadingMore: viewModel.isLoadingMore,
                    hasMore: viewModel.hasMorePages,
                    onRefresh: {
                        await viewModel.refresh()
                    },
                    onLoadMore: {
                        await viewModel.loadMore()
                    },
                    content: { user in
                        UserRowView(user: user)
                    },
                    emptyContent: {
                        NovaEmptyState(
                            icon: "person.2.slash",
                            title: "暂无用户",
                            message: "当前没有找到任何用户",
                            actionTitle: "刷新",
                            action: {
                                Task {
                                    await viewModel.refresh()
                                }
                            }
                        )
                    },
                    errorContent: { error in
                        NovaErrorState(error: error) {
                            Task {
                                await viewModel.loadData()
                            }
                        }
                    }
                )
            }
            .background(DesignColors.surfaceLight)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadData()
        }
    }
}

// MARK: - User Row Component

struct UserRowView: View {
    let user: User

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Avatar with online status
                NovaAvatarWithStatus(
                    emoji: user.avatar,
                    size: 50,
                    isOnline: Bool.random()
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DesignColors.textPrimary)

                    Text(user.email)
                        .font(.system(size: 13))
                        .foregroundColor(DesignColors.textSecondary)
                }

                Spacer()

                NovaSecondaryButton(
                    title: "关注",
                    action: {},
                    fullWidth: false
                )
            }
            .padding(16)

            Divider()
        }
    }
}

// MARK: - Form Example

struct LoginExampleView: View {
    @StateObject private var viewModel = LoginFormViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo or branding
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(DesignColors.brandPrimary)
                        .padding(.top, 40)

                    VStack(spacing: 8) {
                        Text("欢迎回来")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(DesignColors.textPrimary)

                        Text("登录您的账户以继续")
                            .font(.system(size: 15))
                            .foregroundColor(DesignColors.textSecondary)
                    }

                    VStack(spacing: 16) {
                        // Email field
                        NovaTextField(
                            placeholder: "邮箱地址",
                            text: $viewModel.email,
                            icon: "envelope",
                            keyboardType: .emailAddress,
                            autocapitalization: .never,
                            errorMessage: viewModel.validationErrors["email"],
                            onCommit: {
                                _ = viewModel.validateEmail()
                            }
                        )
                        .onChange(of: viewModel.email) { _ in
                            viewModel.clearError(field: "email")
                        }

                        // Password field
                        NovaTextField(
                            placeholder: "密码",
                            text: $viewModel.password,
                            icon: "lock",
                            isSecure: true,
                            errorMessage: viewModel.validationErrors["password"],
                            onCommit: {
                                _ = viewModel.validatePassword()
                            }
                        )
                        .onChange(of: viewModel.password) { _ in
                            viewModel.clearError(field: "password")
                        }

                        // Forgot password
                        HStack {
                            Spacer()
                            NovaTextButton(
                                title: "忘记密码？",
                                action: {
                                    print("Forgot password tapped")
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    // Login button
                    VStack(spacing: 12) {
                        NovaPrimaryButton(
                            title: "登录",
                            action: {
                                Task {
                                    await viewModel.login()
                                }
                            },
                            isLoading: viewModel.formState.isSubmitting,
                            isEnabled: !viewModel.formState.isSubmitting
                        )
                        .padding(.horizontal, 24)

                        // Error message
                        if case .error(let message) = viewModel.formState {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(message)
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                        }

                        // Success message
                        if case .success = viewModel.formState {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("登录成功！")
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        }
                    }

                    // Sign up link
                    HStack(spacing: 4) {
                        Text("还没有账户？")
                            .font(.system(size: 14))
                            .foregroundColor(DesignColors.textSecondary)

                        NovaTextButton(
                            title: "立即注册",
                            action: {
                                print("Sign up tapped")
                            }
                        )
                    }
                    .padding(.top, 8)

                    Spacer()
                }
                .padding(.bottom, 40)
            }
            .background(DesignColors.surfaceLight)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Avatar Gallery Example

struct AvatarGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Story avatars row
                VStack(alignment: .leading, spacing: 12) {
                    Text("Stories")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DesignColors.textPrimary)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // Add story button
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(DesignColors.surfaceElevated)
                                        .frame(width: 70, height: 70)

                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(DesignColors.brandPrimary)
                                }

                                Text("你的")
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignColors.textPrimary)
                            }

                            // User stories
                            ForEach(0..<8, id: \.self) { index in
                                VStack(spacing: 8) {
                                    NovaStoryAvatar(
                                        emoji: ["🎨", "📱", "🌅", "☕️", "🎬", "📸", "🎭", "📚"][index],
                                        hasNewStory: true,
                                        isSeen: index < 3,
                                        onTap: {
                                            print("Story \(index) tapped")
                                        }
                                    )

                                    Text("用户\(index + 1)")
                                        .font(.system(size: 12))
                                        .foregroundColor(DesignColors.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Divider()

                // Avatar group examples
                VStack(spacing: 16) {
                    Text("Group Avatars")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DesignColors.textPrimary)

                    NovaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                NovaAvatarGroup(
                                    emojis: ["👤", "😊", "🎨"],
                                    size: 32
                                )

                                Spacer()

                                Text("3人点赞")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignColors.textSecondary)
                            }

                            Text("你的设计稿")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(DesignColors.textPrimary)

                            Text("Emma、Alex 和其他 1 人觉得很赞")
                                .font(.system(size: 14))
                                .foregroundColor(DesignColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)

                    NovaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                NovaAvatarGroup(
                                    emojis: ["📱", "💬", "🔔", "📸", "🌅", "☕️"],
                                    size: 36,
                                    maxDisplay: 4
                                )

                                Spacer()

                                Text("6人参与")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignColors.textSecondary)
                            }

                            Text("团队会议")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(DesignColors.textPrimary)

                            Text("6 名成员已加入")
                                .font(.system(size: 14))
                                .foregroundColor(DesignColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Divider()

                // Avatar with badges
                VStack(spacing: 16) {
                    Text("Notifications")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DesignColors.textPrimary)

                    HStack(spacing: 32) {
                        VStack(spacing: 8) {
                            NovaAvatarWithBadge(
                                emoji: "💬",
                                size: 60,
                                badgeCount: 5
                            )
                            Text("消息")
                                .font(.system(size: 12))
                                .foregroundColor(DesignColors.textSecondary)
                        }

                        VStack(spacing: 8) {
                            NovaAvatarWithBadge(
                                emoji: "🔔",
                                size: 60,
                                badgeCount: 23
                            )
                            Text("通知")
                                .font(.system(size: 12))
                                .foregroundColor(DesignColors.textSecondary)
                        }

                        VStack(spacing: 8) {
                            NovaAvatarWithBadge(
                                emoji: "❤️",
                                size: 60,
                                badgeCount: 150
                            )
                            Text("点赞")
                                .font(.system(size: 12))
                                .foregroundColor(DesignColors.textSecondary)
                        }
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .background(DesignColors.surfaceLight)
    }
}

// MARK: - Loading States Example

struct LoadingStatesExampleView: View {
    @State private var showLoadingOverlay = false
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Loading States Demo")
                        .font(.system(size: 24, weight: .bold))
                        .padding(.top, 40)

                    // Skeleton screens
                    VStack(spacing: 16) {
                        Text("骨架屏")
                            .font(.headline)

                        NovaPostCardSkeleton()
                        NovaUserListSkeleton()
                        NovaUserListSkeleton()
                    }

                    Divider()

                    // Loading spinners
                    VStack(spacing: 16) {
                        Text("加载指示器")
                            .font(.headline)

                        HStack(spacing: 24) {
                            NovaLoadingSpinner(size: 20)
                            NovaLoadingSpinner(size: 32)
                            NovaLoadingSpinner(size: 44)
                        }
                    }

                    Divider()

                    // Pull to refresh
                    VStack(spacing: 16) {
                        Text("下拉刷新")
                            .font(.headline)

                        NovaPullToRefreshIndicator(isRefreshing: isRefreshing)

                        NovaPrimaryButton(
                            title: isRefreshing ? "刷新中..." : "触发刷新",
                            action: {
                                isRefreshing = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    isRefreshing = false
                                }
                            },
                            fullWidth: false
                        )
                    }

                    Divider()

                    // Loading overlay
                    VStack(spacing: 16) {
                        Text("全屏加载")
                            .font(.headline)

                        NovaPrimaryButton(
                            title: "显示加载遮罩",
                            action: {
                                showLoadingOverlay = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showLoadingOverlay = false
                                }
                            },
                            fullWidth: false
                        )
                    }
                }
                .padding(.bottom, 40)
            }

            if showLoadingOverlay {
                NovaLoadingOverlay(message: "处理中...")
            }
        }
        .background(DesignColors.surfaceLight)
    }
}

// MARK: - Preview

#if DEBUG
struct ExampleUsageView_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            ExampleUsageView()
                .tabItem {
                    Label("列表", systemImage: "list.bullet")
                }

            LoginExampleView()
                .tabItem {
                    Label("表单", systemImage: "person.fill")
                }

            AvatarGalleryView()
                .tabItem {
                    Label("头像", systemImage: "person.circle")
                }

            LoadingStatesExampleView()
                .tabItem {
                    Label("加载", systemImage: "arrow.clockwise")
                }
        }
    }
}
#endif
