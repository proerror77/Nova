import SwiftUI

struct SettingsView: View {
    @Binding var currentPage: AppPage
    @State private var viewModel = SettingsViewModel()
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var pushManager: PushNotificationManager
    @State private var isPostAsExpanded = false
    @State private var selectedPostAsType: PostAsType = .realName
    @State private var isPushEnabled = false

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Navigation Bar
                HStack {
                    Button(action: {
                        currentPage = .account
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18.f, weight: .medium))
                            .frame(width: 24.s, height: 24.s)
                            .foregroundColor(.black)
                    }
                    .accessibilityLabel("Back")
                    .accessibilityHint("Return to account screen")

                    Spacer()

                    Text(LocalizedStringKey("Settings"))
                        .font(Font.custom("SF Pro Display", size: 18.f).weight(.semibold))
                        .lineSpacing(20)
                        .foregroundColor(.black)

                    Spacer()

                    // Placeholder for centering title
                    Color.clear
                        .frame(width: 24.s)
                }
                .padding(EdgeInsets(top: 15.h, leading: 16.w, bottom: 15.h, trailing: 16.w))
                .frame(height: 54.h)

                ScrollView {
                    VStack(spacing: 20.h) {
                    // MARK: - Account Settings Group
                        VStack(spacing: 24.h) {
                            // MARK: - Choose account (可展开)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isPostAsExpanded.toggle()
                                }
                            }) {
                                HStack(spacing: 10.w) {
                                    Image(systemName: "person.crop.square.filled.and.at.rectangle")
                                        .font(.system(size: 18.f, weight: .light))
                                        .foregroundColor(DesignTokens.accentColor)
                                        .frame(width: 24.s, height: 24.s)

                                    Text("Choose account")
                                        .font(Font.custom("SF Pro Display", size: 14.f).weight(.semibold))
                                        .tracking(0.28)
                                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))

                                    Spacer()

                                    Image(systemName: isPostAsExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 12.f))
                                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                                        .frame(width: 24.s, height: 24.s)
                                        .animation(.easeInOut(duration: 0.2), value: isPostAsExpanded)
                                }
                            }
                            .accessibilityLabel("Choose account")
                            .accessibilityHint(isPostAsExpanded ? "Collapse account options" : "Expand to choose which account to post as")
                            .accessibilityAddTraits(.isButton)

                            // 展开的选择面板
                            if isPostAsExpanded {
                                PostAsSelectionPanel(
                                    accounts: buildAccountDisplayData(),
                                    selectedAccountId: viewModel.currentAccountId ?? authManager.currentUser?.id,
                                    onAccountTap: { account in
                                        handleAccountTap(account)
                                    },
                                    pendingPrimaryAvatar: AvatarManager.shared.pendingAvatar,
                                    isLoading: viewModel.isLoadingAccounts && authManager.currentUser == nil
                                )
                            }

                            SettingsRow(
                                icon: "iphone",
                                title: "Devices",
                                showChevron: true,
                                action: {
                                    currentPage = .devices
                                }
                            )
                            .accessibilityLabel("Devices")
                            .accessibilityHint("Manage your connected devices")

                            SettingsRow(
                                icon: "person.badge.key",
                                title: "Passkeys",
                                showChevron: true,
                                action: {
                                    currentPage = .passkeys
                                }
                            )
                            .accessibilityLabel("Passkeys")
                            .accessibilityHint("Manage passkeys for passwordless sign-in")

                            SettingsRow(
                                icon: "person.badge.plus",
                                title: "Invite friends",
                                showChevron: true,
                                action: {
                                    currentPage = .inviteFriends
                                }
                            )
                            .accessibilityLabel("Invite friends")
                            .accessibilityHint("Share Nova Social with your friends")

                            SettingsRow(
                                icon: "display",
                                title: "My channels",
                                showChevron: true,
                                action: {
                                    currentPage = .myChannels
                                }
                            )
                            .accessibilityLabel("My channels")
                            .accessibilityHint("View and manage your channels")
                        }
                        .padding(EdgeInsets(top: 16.h, leading: 24.w, bottom: 16.h, trailing: 24.w))
                        .frame(width: 343.w)
                        .background(.white)
                        .cornerRadius(6.s)

                    // MARK: - Appearance Settings
                        HStack(spacing: 10.w) {
                            Image(systemName: "moon")
                                .font(.system(size: 18.f, weight: .light))
                                .foregroundColor(DesignTokens.accentColor)
                                .frame(width: 24.s, height: 24.s)

                            Text("Dark mode")
                                .font(Font.custom("SF Pro Display", size: 14.f).weight(.semibold))
                                .tracking(0.28)
                                .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))

                            Spacer()

                            // Custom Toggle matching Figma design
                            Button(action: {
                                guard !viewModel.isSavingDarkMode else { return }
                                viewModel.isDarkMode.toggle()
                                Task { await viewModel.updateDarkMode(enabled: viewModel.isDarkMode) }
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10.s)
                                        .fill(viewModel.isDarkMode ? DesignTokens.accentColor : Color(red: 0.77, green: 0.77, blue: 0.77))
                                        .frame(width: 38.w, height: 20.h)
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 14.s, height: 14.s)
                                        .offset(x: viewModel.isDarkMode ? 9.w : -9.w)
                                        .animation(.easeInOut(duration: 0.2), value: viewModel.isDarkMode)
                                }
                                .frame(width: 38.w, height: 20.h)
                            }
                            .accessibilityLabel("Dark mode")
                            .accessibilityHint(viewModel.isDarkMode ? "Turn off dark mode" : "Turn on dark mode")
                        }
                        .padding(.horizontal, 24.w)
                        .frame(width: 343.w, height: 49.h)
                        .background(.white)
                        .cornerRadius(6.s)

                    // MARK: - Notification Settings
                        HStack(spacing: 10.w) {
                            Image(systemName: "bell")
                                .font(.system(size: 18.f, weight: .light))
                                .foregroundColor(DesignTokens.accentColor)
                                .frame(width: 24.s, height: 24.s)

                            Text("Push notifications")
                                .font(Font.custom("SF Pro Display", size: 14.f).weight(.semibold))
                                .tracking(0.28)
                                .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))

                            Spacer()

                            // Custom Toggle matching Figma design
                            Button(action: {
                                Task {
                                    if !isPushEnabled {
                                        let granted = await pushManager.requestAuthorization()
                                        if !granted {
                                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                                await MainActor.run {
                                                    UIApplication.shared.open(settingsUrl)
                                                }
                                            }
                                        } else {
                                            isPushEnabled = true
                                        }
                                    } else {
                                        isPushEnabled = false
                                    }
                                }
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10.s)
                                        .fill(isPushEnabled ? DesignTokens.accentColor : Color(red: 0.77, green: 0.77, blue: 0.77))
                                        .frame(width: 38.w, height: 20.h)
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 14.s, height: 14.s)
                                        .offset(x: isPushEnabled ? 9.w : -9.w)
                                        .animation(.easeInOut(duration: 0.2), value: isPushEnabled)
                                }
                                .frame(width: 38.w, height: 20.h)
                            }
                            .accessibilityLabel("Push notifications")
                            .accessibilityHint(isPushEnabled ? "Disable push notifications" : "Enable push notifications")
                        }
                        .padding(.horizontal, 24.w)
                        .frame(width: 343.w, height: 49.h)
                        .background(.white)
                        .cornerRadius(6.s)
                        .onAppear {
                            isPushEnabled = pushManager.isAuthorized
                        }
                        .onChange(of: pushManager.isAuthorized) { _, newValue in
                            isPushEnabled = newValue
                        }

                    // MARK: - Chat & Data Settings
                        VStack(spacing: 24.h) {
                            SettingsRow(
                                icon: "arrow.up.arrow.down.square",
                                title: "Chat backup",
                                showChevron: true,
                                action: {
                                    currentPage = .chatBackup
                                }
                            )
                            .accessibilityLabel("Chat backup")
                            .accessibilityHint("Export and import your chat conversations")

                            SettingsRow(
                                icon: "waveform.circle",
                                title: "Call recordings",
                                showChevron: true,
                                action: {
                                    currentPage = .callRecordings
                                }
                            )
                            .accessibilityLabel("Call recordings")
                            .accessibilityHint("View and manage your saved call recordings")
                        }
                        .padding(EdgeInsets(top: 16.h, leading: 24.w, bottom: 16.h, trailing: 24.w))
                        .frame(width: 343.w)
                        .background(.white)
                        .cornerRadius(6.s)

                        // MARK: - Actions
                        Button(action: {
                            Task {
                                await viewModel.logout()
                            }
                        }) {
                            HStack(spacing: 10.w) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18.f, weight: .light))
                                    .foregroundColor(DesignTokens.accentColor)
                                    .frame(width: 24.s, height: 24.s)

                                Text("Sign out")
                                    .font(Font.custom("Helvetica Neue", size: 14.f).weight(.medium))
                                    .lineSpacing(19.06)
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                                Spacer()
                            }
                            .padding(.leading, 24.w)
                        }
                        .frame(width: 343.w, height: 49.h)
                        .background(.white)
                        .cornerRadius(6.s)
                        .accessibilityLabel("Sign out")
                        .accessibilityHint("Sign out of your account")
                    }
                    .padding(EdgeInsets(top: 20.h, leading: 0, bottom: 20.h, trailing: 0))
                }

                Spacer()
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                Text(LocalizedStringKey(error))
                    .font(Font.custom("SF Pro Display", size: 13.f).weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12.w)
                    .padding(.vertical, 8.h)
                    .background(Color.red.opacity(0.9))
                    .cornerRadius(12.s)
                    .padding(.top, 12.h)
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
    }

    // MARK: - Account Display Helpers

    /// Build account display data from viewModel accounts
    /// 使用乐观 UI 策略：优先显示本地数据，避免不必要的 loading 状态
    private func buildAccountDisplayData() -> [AccountDisplayData] {
        var displayAccounts: [AccountDisplayData] = []

        // Primary account: 优先使用 API 返回的第一个非 alias 账户
        // 不依赖 isPrimary 字段（API 可能不返回），而是用 !isAlias 判断
        if let primary = viewModel.accounts.first(where: { !$0.isAlias }) {
            displayAccounts.append(AccountDisplayData(from: primary))
        } else if let user = authManager.currentUser {
            // Fallback: 使用 @EnvironmentObject 中的当前用户
            displayAccounts.append(AccountDisplayData(fromUser: user))
        }

        // Alias account: 根据加载状态显示不同内容
        if let alias = viewModel.aliasAccounts.first {
            // API 返回了别名账户
            displayAccounts.append(AccountDisplayData(from: alias))
        } else if viewModel.hasLoadedAccounts {
            // API 已完成，确认没有别名 → 显示 "Create Alias"
            displayAccounts.append(.placeholderAlias)
        } else {
            // API 还在加载中 → 显示 "Loading..."
            displayAccounts.append(.loadingAlias)
        }

        return displayAccounts
    }

    /// Handle account tap action
    private func handleAccountTap(_ account: AccountDisplayData) {
        if account.isAlias {
            if account.id == AccountDisplayData.loadingAliasID {
                // 加载中，忽略点击
                return
            } else if account.id == AccountDisplayData.placeholderAliasID {
                // Navigate to create alias
                viewModel.createNewAliasAccount()
                currentPage = .aliasName
            } else {
                // Navigate to edit alias
                if let aliasAccount = viewModel.aliasAccounts.first(where: { $0.id == account.id }) {
                    viewModel.editAliasAccount(aliasAccount)
                }
                currentPage = .aliasName
            }
        } else {
            // Navigate to profile settings
            currentPage = .profileSetting
        }
    }
}

// MARK: - Previews

#Preview("Settings - Default") {
    SettingsView(currentPage: .constant(.setting))
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(PushNotificationManager.shared)
}

#Preview("Settings - Dark Mode") {
    SettingsView(currentPage: .constant(.setting))
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(PushNotificationManager.shared)
        .preferredColorScheme(.dark)
}
