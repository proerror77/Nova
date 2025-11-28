import SwiftUI

struct SettingsView: View {
    @Binding var currentPage: AppPage
    @State private var isDarkMode = false
    @StateObject private var authManager = AuthenticationManager.shared

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .account
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(Color.white)

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - 第一组设置项
                        VStack(spacing: 0) {
                            SettingsRow(
                                icon: "person.2",
                                title: "Profile Settings",
                                showChevron: true,
                                action: {
                                    currentPage = .profileSetting
                                }
                            )

                            Divider()
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "person.circle",
                                title: "My Account",
                                showChevron: true,
                                action: {
                                    currentPage = .accounts
                                }
                            )

                            Divider()
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "iphone",
                                title: "Devices",
                                showChevron: true,
                                action: {
                                    currentPage = .devices
                                }
                            )

                            Divider()
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "person.badge.plus",
                                title: "Invite Friends",
                                showChevron: true,
                                action: {
                                    currentPage = .inviteFriends
                                }
                            )

                            Divider()
                                .padding(.leading, 50)

                            SettingsRow(
                                icon: "tv",
                                title: "My Channels",
                                showChevron: true,
                                action: {
                                    currentPage = .myChannels
                                }
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.68, green: 0.68, blue: 0.68), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)

                        // MARK: - Dark Mode
                        HStack {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(red: 0.82, green: 0.11, blue: 0.26))
                                .frame(width: 24)

                            Text("Dark Mode")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                            Spacer()

                            Toggle("", isOn: $isDarkMode)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.68, green: 0.68, blue: 0.68), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)

                        // MARK: - Sign Out
                        Button(action: {
                            Task {
                                await authManager.logout()
                            }
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color(red: 0.82, green: 0.11, blue: 0.26))
                                    .frame(width: 24)

                                Text("Sign Out")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.68, green: 0.68, blue: 0.68), lineWidth: 0.5)
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
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.82, green: 0.11, blue: 0.26))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color.gray.opacity(0.5))
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
