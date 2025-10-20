import SwiftUI

/// View for selecting the app language
struct LanguageSelectionView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLanguage: Language
    @State private var showRestartAlert = false

    init() {
        _selectedLanguage = State(initialValue: LocalizationManager.shared.currentLanguage)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Language.allCases) { language in
                        LanguageRow(
                            language: language,
                            isSelected: selectedLanguage == language
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleLanguageSelection(language)
                        }
                    }
                } header: {
                    Text(L10n.LanguageSelection.title)
                } footer: {
                    Text("language_selection.footer".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(L10n.Settings.language)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
            .alert("language_selection.changed_title".localized, isPresented: $showRestartAlert) {
                Button(L10n.Common.ok, role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("language_selection.changed_message".localized)
            }
        }
    }

    // MARK: - Actions

    private func handleLanguageSelection(_ language: Language) {
        guard language != selectedLanguage else { return }

        selectedLanguage = language
        localizationManager.setLanguage(language)
        showRestartAlert = true
    }
}

// MARK: - Language Row
private struct LanguageRow: View {
    let language: Language
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Language name
            VStack(alignment: .leading, spacing: 4) {
                Text(language.nativeName)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(language.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Checkmark
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View with Language Option
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLanguageSelection = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section(L10n.Settings.account) {
                    NavigationLink {
                        Text("Edit Profile")
                    } label: {
                        SettingsRow(
                            icon: "person.circle",
                            title: L10n.Profile.editProfile,
                            iconColor: .blue
                        )
                    }
                }

                // App Settings Section
                Section(L10n.Settings.title) {
                    Button {
                        showLanguageSelection = true
                    } label: {
                        SettingsRow(
                            icon: "globe",
                            title: L10n.Settings.language,
                            iconColor: .green,
                            detail: LocalizationManager.shared.currentLanguage.nativeName
                        )
                    }

                    NavigationLink {
                        Text("Notifications Settings")
                    } label: {
                        SettingsRow(
                            icon: "bell.fill",
                            title: L10n.Settings.notifications,
                            iconColor: .orange
                        )
                    }

                    NavigationLink {
                        Text("Privacy Settings")
                    } label: {
                        SettingsRow(
                            icon: "lock.fill",
                            title: L10n.Settings.privacy,
                            iconColor: .purple
                        )
                    }
                }

                // About Section
                Section(L10n.Settings.about) {
                    NavigationLink {
                        Text("Terms of Service")
                    } label: {
                        SettingsRow(
                            icon: "doc.text",
                            title: "settings.terms_of_service".localized,
                            iconColor: .gray
                        )
                    }

                    NavigationLink {
                        Text("Privacy Policy")
                    } label: {
                        SettingsRow(
                            icon: "hand.raised.fill",
                            title: "settings.privacy_policy".localized,
                            iconColor: .gray
                        )
                    }

                    NavigationLink {
                        Text("Help & Support")
                    } label: {
                        SettingsRow(
                            icon: "questionmark.circle",
                            title: "settings.help".localized,
                            iconColor: .gray
                        )
                    }
                }

                // Logout Section
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(L10n.Settings.logout)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }

                // App Version
                Section {
                    HStack {
                        Text(L10n.Settings.version)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1.0.0 (1)")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle(L10n.Settings.title)
            .sheet(isPresented: $showLanguageSelection) {
                LanguageSelectionView()
            }
            .alert(L10n.Settings.logout, isPresented: $showLogoutConfirm) {
                Button(L10n.Common.cancel, role: .cancel) { }
                Button(L10n.Settings.logout, role: .destructive) {
                    handleLogout()
                }
            } message: {
                Text("settings.logout_confirm".localized)
            }
        }
    }

    private func handleLogout() {
        // Handle logout logic
        appState.isAuthenticated = false
    }
}

// MARK: - Settings Row Component
private struct SettingsRow: View {
    let icon: String
    let title: String
    let iconColor: Color
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(iconColor)
                .cornerRadius(6)

            Text(title)

            Spacer()

            if let detail = detail {
                Text(detail)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview
#Preview("Language Selection") {
    LanguageSelectionView()
        .environmentObject(LocalizationManager.shared)
}

#Preview("Settings") {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(LocalizationManager.shared)
}
