import SwiftUI

struct SettingsView: View {
    @Binding var currentPage: AppPage
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var isPostAsExpanded = false
    @State private var selectedPostAsType: PostAsType = .realName

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

                    Spacer()

                    Text(LocalizedStringKey("Settings"))
                        .font(Typography.semibold24)
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
                                SettingsRow(
                                    icon: "person.crop.circle",
                                    title: "Profile Settings",
                                    showChevron: true,
                                    action: {
                                        currentPage = .profileSetting
                                    }
                                )

                                Divider()
                                    .padding(.leading, 60)

                                // MARK: - Post As (可展开)
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        isPostAsExpanded.toggle()
                                    }
                                }) {
                                    HStack(spacing: 16) {
                                        Image(systemName: "person.crop.square.filled.and.at.rectangle")
                                            .font(Typography.regular18)
                                            .foregroundColor(DesignTokens.accentColor)
                                            .frame(width: 24)

                                        Text("Post as")
                                            .font(Typography.semibold14)
                                            .foregroundColor(DesignTokens.textPrimary)

                                        Spacer()

                                        Image(systemName: isPostAsExpanded ? "chevron.down" : "chevron.right")
                                            .font(Typography.regular12)
                                            .foregroundColor(DesignTokens.textSecondary)
                                            .animation(.easeInOut(duration: 0.2), value: isPostAsExpanded)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                }

                                // 展开的选择面板 - 使用高度动画
                                PostAsSelectionPanel(
                                    selectedType: $selectedPostAsType,
                                    realName: authManager.currentUser?.displayName ?? authManager.currentUser?.username ?? "User",
                                    username: authManager.currentUser?.username ?? "username",
                                    avatarUrl: authManager.currentUser?.avatarUrl
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
                                    .font(Typography.regular18)
                                    .foregroundColor(DesignTokens.accentColor)
                                    .frame(width: 24)

                                Text("Dark Mode")
                                    .font(Typography.semibold14)
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
                                        .font(Typography.regular18)
                                        .foregroundColor(DesignTokens.accentColor)
                                        .frame(width: 24)

                                    Text("Sign Out")
                                        .font(Typography.semibold14)
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
                    .font(Typography.semibold13)
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
}

#Preview {
    SettingsView(currentPage: .constant(.setting))
        .environmentObject(AuthenticationManager.shared)
}
