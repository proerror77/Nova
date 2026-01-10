import SwiftUI
import UIKit

// MARK: - Post As Type (Legacy compatibility)

enum PostAsType {
    case realName
    case alias
}

// MARK: - Account Display Data

/// Simple data structure for displaying account in UI
/// Used to decouple UI from the Account model
struct AccountDisplayData: Identifiable {
    // MARK: - Constants
    static let placeholderAliasID = "placeholder-alias"
    static let loadingAliasID = "loading-alias"

    let id: String
    let displayName: String
    let subtitle: String
    let avatarUrl: String?
    let isAlias: Bool
    let isPrimary: Bool
    let isActive: Bool

    /// Memberwise initializer
    init(
        id: String,
        displayName: String,
        subtitle: String,
        avatarUrl: String?,
        isAlias: Bool,
        isPrimary: Bool,
        isActive: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.avatarUrl = avatarUrl
        self.isAlias = isAlias
        self.isPrimary = isPrimary
        self.isActive = isActive
    }

    /// Create from Account model
    init(from account: Account) {
        self.id = account.id
        self.displayName = account.effectiveDisplayName
        // For alias accounts, show profession or location as subtitle
        if account.isAlias {
            if let profession = account.profession, !profession.isEmpty {
                self.subtitle = profession
            } else if let location = account.location, !location.isEmpty {
                self.subtitle = location
            } else {
                self.subtitle = "Alias name"
            }
        } else {
            self.subtitle = "@\(account.username)"
        }
        self.avatarUrl = account.avatarUrl
        self.isAlias = account.isAlias
        self.isPrimary = account.isPrimary
        self.isActive = account.isActive
    }

    /// Create from user profile (for primary account fallback)
    init(fromUser user: UserProfile) {
        self.id = user.id
        self.displayName = user.fullName
        self.subtitle = "@\(user.username)"
        self.avatarUrl = user.avatarUrl
        self.isAlias = false
        self.isPrimary = true
        self.isActive = true
    }

    /// Create placeholder for alias when none exists
    static var placeholderAlias: AccountDisplayData {
        AccountDisplayData(
            id: placeholderAliasID,
            displayName: "Create Alias",
            subtitle: "Set up your alias name",
            avatarUrl: nil,
            isAlias: true,
            isPrimary: false,
            isActive: false
        )
    }

    /// Create loading placeholder for alias while fetching from API
    static var loadingAlias: AccountDisplayData {
        AccountDisplayData(
            id: loadingAliasID,
            displayName: "Loading...",
            subtitle: "Checking alias account",
            avatarUrl: nil,
            isAlias: true,
            isPrimary: false,
            isActive: false
        )
    }
}

// MARK: - Post As Selection Panel

struct PostAsSelectionPanel: View {
    /// Accounts to display
    let accounts: [AccountDisplayData]

    /// Currently selected account ID
    let selectedAccountId: String?

    /// Callback when account is tapped
    let onAccountTap: (AccountDisplayData) -> Void

    /// Optional: pending avatar for primary account (from AvatarManager)
    var pendingPrimaryAvatar: UIImage?

    /// Whether accounts are being loaded
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 24.h) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading accounts...")
                        .font(Font.custom("SF Pro Display", size: 14.f))
                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                }
                .padding(.vertical, 20.h)
            } else if accounts.isEmpty {
                Text("No accounts available")
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                    .padding(.vertical, 20.h)
            } else {
                ForEach(accounts) { account in
                    PostAsOptionRow(
                        avatarUrl: account.avatarUrl,
                        displayName: account.displayName,
                        subtitle: account.subtitle,
                        isSelected: account.id == selectedAccountId,
                        isAlias: account.isAlias,
                        borderColor: account.isAlias
                            ? Color(red: 0.75, green: 0.75, blue: 0.75)
                            : Color(red: 0.87, green: 0.11, blue: 0.26),
                        action: { onAccountTap(account) },
                        pendingAvatar: account.isPrimary ? pendingPrimaryAvatar : nil
                    )
                }
            }
        }
        .padding(.horizontal, 17.w)
        .padding(.vertical, 16.h)
        .frame(width: 313.w)
        .cornerRadius(6.s)
        .overlay(
            RoundedRectangle(cornerRadius: 6.s)
                .inset(by: 0.25)
                .stroke(Color(red: 0.90, green: 0.90, blue: 0.90), lineWidth: 0.25)
        )
    }
}

// MARK: - Convenience initializer for backward compatibility

extension PostAsSelectionPanel {
    /// Legacy initializer for backward compatibility
    /// - Parameters:
    ///   - selectedType: The selected post type binding
    ///   - realName: User's real display name
    ///   - username: User's username
    ///   - avatarUrl: User's avatar URL
    ///   - aliasName: Optional alias name (fetched from API)
    ///   - aliasAvatarUrl: Optional alias avatar URL
    ///   - onRealNameTap: Callback when real name option is tapped
    ///   - onAliasTap: Callback when alias option is tapped
    init(
        selectedType: Binding<PostAsType>,
        realName: String,
        username: String,
        avatarUrl: String?,
        aliasName: String? = nil,
        aliasAvatarUrl: String? = nil,
        onRealNameTap: (() -> Void)? = nil,
        onAliasTap: (() -> Void)? = nil
    ) {
        // Create display data from legacy parameters
        let primaryAccount = AccountDisplayData(
            id: "primary",
            displayName: realName,
            subtitle: "@\(username)",
            avatarUrl: avatarUrl,
            isAlias: false,
            isPrimary: true,
            isActive: true
        )

        let aliasAccount = AccountDisplayData(
            id: "alias",
            displayName: aliasName ?? "Create Alias",
            subtitle: aliasName != nil ? "Alias name" : "Set up your alias",
            avatarUrl: aliasAvatarUrl,
            isAlias: true,
            isPrimary: false,
            isActive: false
        )

        self.accounts = [primaryAccount, aliasAccount]
        self.selectedAccountId = selectedType.wrappedValue == .realName ? "primary" : "alias"
        self.pendingPrimaryAvatar = AvatarManager.shared.pendingAvatar
        self.isLoading = false

        self.onAccountTap = { account in
            if account.isAlias {
                onAliasTap?()
            } else {
                onRealNameTap?()
            }
        }
    }
}

// MARK: - Post As Option Row

struct PostAsOptionRow: View {
    let avatarUrl: String?
    let displayName: String
    let subtitle: String
    let isSelected: Bool
    let isAlias: Bool
    let borderColor: Color
    let action: () -> Void
    var pendingAvatar: UIImage? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8.w) {
                // Avatar - 35x35 frame with 30x30 content
                ZStack {
                    if let pendingAvatar = pendingAvatar {
                        Image(uiImage: pendingAvatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30.s, height: 30.s)
                            .clipShape(Circle())
                    } else if let avatarUrl = avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            DefaultAvatarView(size: 30.s)
                        }
                        .frame(width: 30.s, height: 30.s)
                        .clipShape(Circle())
                    } else {
                        DefaultAvatarView(size: 30.s)
                    }
                }
                .frame(width: 35.s, height: 35.s)
                .cornerRadius(28.s)
                .overlay(
                    RoundedRectangle(cornerRadius: 28.s)
                        .inset(by: 0.5)
                        .stroke(borderColor, lineWidth: 0.5)
                )

                // Name and subtitle
                VStack(alignment: .leading, spacing: 1.h) {
                    Text(displayName)
                        .font(Font.custom("SF Pro Display", size: 14.f).weight(.semibold))
                        .tracking(0.28)
                        .foregroundColor(.black)

                    Text(subtitle)
                        .font(Font.custom("SF Pro Display", size: 10.f))
                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                }

                Spacer()

                // Chevron for navigation
                Image(systemName: "chevron.right")
                    .font(.system(size: 12.f))
                    .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                    .frame(width: 24.s, height: 24.s)
            }
        }
    }
}

// MARK: - Previews

#Preview("With Accounts") {
    let accounts = [
        AccountDisplayData(
            id: "1",
            displayName: "Bruce Li",
            subtitle: "@brucelichina",
            avatarUrl: nil,
            isAlias: false,
            isPrimary: true,
            isActive: true
        ),
        AccountDisplayData(
            id: "2",
            displayName: "Dreamer",
            subtitle: "Alias name",
            avatarUrl: nil,
            isAlias: true,
            isPrimary: false,
            isActive: false
        )
    ]

    VStack {
        PostAsSelectionPanel(
            accounts: accounts,
            selectedAccountId: "1",
            onAccountTap: { _ in }
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

#Preview("Loading State") {
    VStack {
        PostAsSelectionPanel(
            accounts: [],
            selectedAccountId: nil,
            onAccountTap: { _ in },
            isLoading: true
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

#Preview("Legacy Compatibility") {
    VStack {
        PostAsSelectionPanel(
            selectedType: .constant(.realName),
            realName: "Bruce Li",
            username: "brucelichina",
            avatarUrl: nil
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
