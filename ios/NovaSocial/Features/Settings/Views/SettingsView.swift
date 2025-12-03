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
                    VStack(spacing: 16) {
                        // MARK: - First Settings Group
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
                        .background(DesignTokens.surface)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)

                        // MARK: - Dark Mode
                        HStack {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 18))
                                .foregroundColor(DesignTokens.accentColor)
                                .frame(width: 24)

                            Text(LocalizedStringKey("Dark Mode"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignTokens.textPrimary)

                            Spacer()

                            if viewModel.isSavingDarkMode {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Toggle("", isOn: $viewModel.isDarkMode)
                                    .labelsHidden()
                                    .onChange(of: viewModel.isDarkMode) { _, newValue in
                                        Task { await viewModel.updateDarkMode(enabled: newValue) }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(DesignTokens.surface)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !viewModel.isSavingDarkMode else { return }
                            viewModel.isDarkMode.toggle()
                        }

                        // MARK: - Sign Out
                        Button(action: {
                            Task {
                                await viewModel.logout()
                            }
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18))
                                    .foregroundColor(DesignTokens.accentColor)
                                    .frame(width: 24)

                                Text(LocalizedStringKey("Sign Out"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(DesignTokens.textPrimary)

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(DesignTokens.surface)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor, lineWidth: 0.5)
                        )
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
