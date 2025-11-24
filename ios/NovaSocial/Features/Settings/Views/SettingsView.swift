import SwiftUI

struct SettingsView: View {
    @Binding var currentPage: AppPage

    // 直接引用 ThemeManager.shared，SwiftUI 会自动追踪 @Observable 的变化
    private var themeManager: ThemeManager {
        ThemeManager.shared
    }

    var body: some View {
        ZStack {
            DesignTokens.background  // ✨ 使用新的便捷属性
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .account
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.text)  // ✨ 更简洁
                    }

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.text)  // ✨ 更简洁

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(DesignTokens.card)  // ✨ 使用新的便捷属性

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - 第一组设置项
                        VStack(spacing: 0) {
                            SettingsRow(
                                icon: "person.2",
                                title: "Profile Settings",
                                showChevron: true,
                                isDark: themeManager.isDarkMode,
                                action: {
                                    currentPage = .profileSetting
                                }
                            )

                            Divider()
                                .background(DesignTokens.dividerColor(isDark: themeManager.isDarkMode))
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "person.circle",
                                title: "My Account",
                                showChevron: true,
                                isDark: themeManager.isDarkMode,
                                action: {
                                    currentPage = .accounts
                                }
                            )

                            Divider()
                                .background(DesignTokens.dividerColor(isDark: themeManager.isDarkMode))
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "iphone",
                                title: "Devices",
                                showChevron: true,
                                isDark: themeManager.isDarkMode,
                                action: {
                                    currentPage = .devices
                                }
                            )

                            Divider()
                                .background(DesignTokens.dividerColor(isDark: themeManager.isDarkMode))
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "person.badge.plus",
                                title: "Invite Friends",
                                showChevron: true,
                                isDark: themeManager.isDarkMode,
                                action: {
                                    currentPage = .inviteFriends
                                }
                            )

                            Divider()
                                .background(DesignTokens.dividerColor(isDark: themeManager.isDarkMode))
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "tv",
                                title: "My Channels",
                                showChevron: true,
                                isDark: themeManager.isDarkMode,
                                action: {
                                    currentPage = .myChannels
                                }
                            )
                        }
                        .background(DesignTokens.cardBackground(isDark: themeManager.isDarkMode))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor(isDark: themeManager.isDarkMode), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)

                        // MARK: - Dark Mode
                        HStack {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 18))
                                .foregroundColor(DesignTokens.accentColor(isDark: themeManager.isDarkMode))
                                .frame(width: 24)

                            Text("Dark Mode")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignTokens.textPrimary(isDark: themeManager.isDarkMode))

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { themeManager.isDarkMode },
                                set: { themeManager.isDarkMode = $0 }
                            ))
                                .labelsHidden()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(DesignTokens.cardBackground(isDark: themeManager.isDarkMode))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor(isDark: themeManager.isDarkMode), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)

                        // MARK: - Sign Out
                        Button(action: {
                            // 退出登录，跳转到 Login 页面
                            currentPage = .login
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18))
                                    .foregroundColor(DesignTokens.accentColor(isDark: themeManager.isDarkMode))
                                    .frame(width: 24)

                                Text("Sign Out")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(DesignTokens.textPrimary(isDark: themeManager.isDarkMode))

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(DesignTokens.cardBackground(isDark: themeManager.isDarkMode))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor(isDark: themeManager.isDarkMode), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)
                    }
                    .padding(.top, 20)
                }

                Spacer()
            }
        }
    }
}

// MARK: - 设置行组件
struct SettingsRow: View {
    let icon: String
    let title: String
    var showChevron: Bool = false
    var isDark: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(DesignTokens.accentColor(isDark: isDark))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.textPrimary(isDark: isDark))

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textSecondary(isDark: isDark))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    SettingsView(currentPage: .constant(.setting))
}
