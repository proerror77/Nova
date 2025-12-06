import SwiftUI

struct SettingsView: View {
    @Binding var currentPage: AppPage
    @StateObject private var viewModel = SettingsViewModel()

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
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    Text(LocalizedStringKey("Settings"))
                        .font(.system(size: 24, weight: .medium))
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
                            // Section Header
                            Text("ACCOUNT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)

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

                                SettingsRow(
                                    icon: "person.crop.square.filled.and.at.rectangle",
                                    title: "Post as",
                                    showChevron: true,
                                    action: {
                                        // TODO: 实现Post as功能
                                        print("Post as tapped - feature coming soon")
                                    }
                                )

                                Divider()
                                    .padding(.leading, 60)

                                SettingsRow(
                                    icon: "person.text.rectangle",
                                    title: "My Account",
                                    showChevron: true,
                                    action: {
                                        currentPage = .accounts
                                    }
                                )

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
                            // Section Header
                            Text("APPEARANCE")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)

                            HStack(spacing: 16) {
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(DesignTokens.accentColor)
                                    .frame(width: 24)

                                Text("Dark Mode")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

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
                                        .font(.system(size: 18))
                                        .foregroundColor(.red)
                                        .frame(width: 24)

                                    Text("Sign Out")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

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
                    .font(.system(size: 13, weight: .semibold))
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
}
