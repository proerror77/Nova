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
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Navigation Bar
                HStack {
                    Button(action: {
                        currentPage = .account
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                    .accessibilityLabel("Back")
                    .accessibilityHint("Return to account screen")

                    Spacer()

                    Text(LocalizedStringKey("Settings"))
                        .font(Font.custom("SFProDisplay-Medium", size: 24.f))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // Placeholder for centering title
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(DesignTokens.surface)

                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - Account Settings Group
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(spacing: 0) {
                                // MARK: - Choose account (可展开)
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        isPostAsExpanded.toggle()
                                    }
                                }) {
                                    HStack(spacing: 16) {
                                        Image(systemName: "person.crop.square.filled.and.at.rectangle")
                                            .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                                            .foregroundColor(DesignTokens.accentColor)
                                            .frame(width: 24)

                                        Text("Choose account")
                                            .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                                            .foregroundColor(DesignTokens.textPrimary)

                                        Spacer()

                                        Image(systemName: isPostAsExpanded ? "chevron.down" : "chevron.right")
                                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                            .foregroundColor(DesignTokens.textSecondary)
                                            .animation(.easeInOut(duration: 0.2), value: isPostAsExpanded)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                }
                                .accessibilityLabel("Choose account")
                                .accessibilityHint(isPostAsExpanded ? "Collapse account options" : "Expand to choose which account to post as")
                                .accessibilityAddTraits(.isButton)

                                // 展开的选择面板 - 使用高度动画
                                // 优化：只有在完全没有数据时才显示 loading
                                // 否则立即显示 authManager.currentUser 数据
                                PostAsSelectionPanel(
                                    accounts: buildAccountDisplayData(),
                                    selectedAccountId: viewModel.currentAccountId ?? authManager.currentUser?.id,
                                    onAccountTap: { account in
                                        handleAccountTap(account)
                                    },
                                    pendingPrimaryAvatar: AvatarManager.shared.pendingAvatar,
                                    isLoading: viewModel.isLoadingAccounts && authManager.currentUser == nil
                                )
                                .frame(height: isPostAsExpanded ? nil : 0, alignment: .top)
                                .clipped()
                                .opacity(isPostAsExpanded ? 1 : 0)

                                Divider()
                                    .padding(.leading, 60)

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

                                Divider()
                                    .padding(.leading, 60)

                                SettingsRow(
                                    icon: "person.badge.key.fill",
                                    title: "Passkeys",
                                    showChevron: true,
                                    action: {
                                        currentPage = .passkeys
                                    }
                                )
                                .accessibilityLabel("Passkeys")
                                .accessibilityHint("Manage passkeys for passwordless sign-in")

                                Divider()
                                    .padding(.leading, 60)

                                SettingsRow(
                                    icon: "person.badge.plus",
                                    title: "Invite Friends",
                                    showChevron: true,
                                    action: {
                                        currentPage = .inviteFriends
                                    }
                                )
                                .accessibilityLabel("Invite Friends")
                                .accessibilityHint("Share Nova Social with your friends")

                                Divider()
                                    .padding(.leading, 60)

                                SettingsRow(
                                    icon: "tv",
                                    title: "My Channels",
                                    showChevron: true,
                                    action: {
                                        currentPage = .myChannels
                                    }
                                )
                                .accessibilityLabel("My Channels")
                                .accessibilityHint("View and manage your channels")
                            }
                            .background(DesignTokens.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.68, green: 0.68, blue: 0.68).opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }
                        .padding(.horizontal, 12)

                        // MARK: - Appearance Settings
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 16) {
                                Image(systemName: "moon.fill")
                                    .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                                    .foregroundColor(DesignTokens.accentColor)
                                    .frame(width: 24)

                                Text("Dark Mode")
                                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                                    .foregroundColor(DesignTokens.textPrimary)

                                Spacer()

                                if viewModel.isSavingDarkMode {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Toggle("", isOn: $viewModel.isDarkMode)
                                        .labelsHidden()
                                        .tint(DesignTokens.accentColor)
                                        .onChange(of: viewModel.isDarkMode) { _, newValue in
                                            Task { await viewModel.updateDarkMode(enabled: newValue) }
                                        }
                                        .accessibilityLabel("Dark Mode")
                                        .accessibilityHint(viewModel.isDarkMode ? "Turn off dark mode" : "Turn on dark mode")
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(DesignTokens.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.68, green: 0.68, blue: 0.68).opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !viewModel.isSavingDarkMode else { return }
                                viewModel.isDarkMode.toggle()
                            }
                            .accessibilityElement(children: .contain)
                        }
                        .padding(.horizontal, 12)

                        // MARK: - Notification Settings
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 16) {
                                Image(systemName: "bell.fill")
                                    .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                                    .foregroundColor(DesignTokens.accentColor)
                                    .frame(width: 24)

                                Text("Push Notifications")
                                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                                    .foregroundColor(DesignTokens.textPrimary)

                                Spacer()

                                Toggle("", isOn: $isPushEnabled)
                                    .labelsHidden()
                                    .tint(DesignTokens.accentColor)
                                    .onChange(of: isPushEnabled) { _, newValue in
                                        Task {
                                            if newValue {
                                                let granted = await pushManager.requestAuthorization()
                                                if !granted {
                                                    // Open system settings if permission denied
                                                    isPushEnabled = false
                                                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                                        await MainActor.run {
                                                            UIApplication.shared.open(settingsUrl)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .accessibilityLabel("Push Notifications")
                                    .accessibilityHint(isPushEnabled ? "Disable push notifications" : "Enable push notifications")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(DesignTokens.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.68, green: 0.68, blue: 0.68).opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isPushEnabled.toggle()
                            }
                            .accessibilityElement(children: .contain)
                        }
                        .padding(.horizontal, 12)
                        .onAppear {
                            isPushEnabled = pushManager.isAuthorized
                        }
                        .onChange(of: pushManager.isAuthorized) { _, newValue in
                            isPushEnabled = newValue
                        }

                        // MARK: - Chat & Data Settings
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(spacing: 0) {
                                SettingsRow(
                                    icon: "arrow.up.arrow.down.square",
                                    title: "Chat Backup",
                                    showChevron: true,
                                    action: {
                                        currentPage = .chatBackup
                                    }
                                )
                                .accessibilityLabel("Chat Backup")
                                .accessibilityHint("Export and import your chat conversations")

                                Divider()
                                    .padding(.leading, 60)

                                SettingsRow(
                                    icon: "waveform.circle",
                                    title: "Call Recordings",
                                    showChevron: true,
                                    action: {
                                        currentPage = .callRecordings
                                    }
                                )
                                .accessibilityLabel("Call Recordings")
                                .accessibilityHint("View and manage your saved call recordings")
                            }
                            .background(DesignTokens.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.68, green: 0.68, blue: 0.68).opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }
                        .padding(.horizontal, 12)

                        // MARK: - Actions
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: {
                                Task {
                                    await viewModel.logout()
                                }
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                                        .foregroundColor(DesignTokens.accentColor)
                                        .frame(width: 24)

                                    Text("Sign Out")
                                        .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                                        .foregroundColor(DesignTokens.textPrimary)

                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            }
                            .background(DesignTokens.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.68, green: 0.68, blue: 0.68).opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            .accessibilityLabel("Sign Out")
                            .accessibilityHint("Sign out of your account")
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.top, 20)
                }

                Spacer()
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                Text(LocalizedStringKey(error))
                    .font(Font.custom("SFProDisplay-Semibold", size: 13.f))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.9))
                    .cornerRadius(12)
                    .padding(.top, 12)
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
