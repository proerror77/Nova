import SwiftUI
import UIKit

// 发帖身份类型
enum PostAsType: Equatable {
    case primary
    case alias(accountId: String)
}

struct PostAsSelectionPanel: View {
    @Binding var selectedType: PostAsType
    let primaryAccount: Account?
    let aliasAccounts: [Account]
    let currentUser: UserProfile?
    var onPrimaryTap: (() -> Void)? = nil
    var onAliasTap: ((Account?) -> Void)? = nil

    // Computed properties for backward compatibility
    private var realName: String {
        primaryAccount?.effectiveDisplayName ?? currentUser?.displayName ?? currentUser?.username ?? "User"
    }

    private var username: String {
        primaryAccount?.username ?? currentUser?.username ?? "username"
    }

    private var avatarUrl: String? {
        primaryAccount?.avatarUrl ?? currentUser?.avatarUrl
    }

    var body: some View {
        VStack(spacing: 0) {
            // 主账户选项
            PostAsOptionRow(
                avatarUrl: avatarUrl,
                displayName: realName,
                subtitle: username,
                isSelected: selectedType == .primary,
                borderColor: Color(red: 0.82, green: 0.11, blue: 0.26),
                action: { onPrimaryTap?() },
                pendingAvatar: AvatarManager.shared.pendingAvatar
            )

            // 分隔线
            if !aliasAccounts.isEmpty {
                Divider()
                    .padding(.leading, 80)
            }

            // 子账户选项列表
            ForEach(aliasAccounts) { alias in
                PostAsOptionRow(
                    avatarUrl: alias.avatarUrl,
                    displayName: alias.effectiveDisplayName,
                    subtitle: "Alias name",
                    isSelected: {
                        if case .alias(let id) = selectedType {
                            return id == alias.id
                        }
                        return false
                    }(),
                    borderColor: Color(red: 0.37, green: 0.37, blue: 0.37),
                    action: { onAliasTap?(alias) }
                )

                if alias.id != aliasAccounts.last?.id {
                    Divider()
                        .padding(.leading, 80)
                }
            }

            // 如果没有子账户，显示创建选项
            if aliasAccounts.isEmpty {
                Divider()
                    .padding(.leading, 80)

                PostAsOptionRow(
                    avatarUrl: nil,
                    displayName: "Create Alias",
                    subtitle: "Add a new identity",
                    isSelected: false,
                    borderColor: Color(red: 0.37, green: 0.37, blue: 0.37),
                    action: { onAliasTap?(nil) },
                    showAddIcon: true
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77).opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

struct PostAsOptionRow: View {
    let avatarUrl: String?
    let displayName: String
    let subtitle: String
    let isSelected: Bool
    let borderColor: Color
    let action: () -> Void
    var pendingAvatar: UIImage? = nil
    var showAddIcon: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // 头像
                ZStack {
                    if showAddIcon {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
                            .frame(width: 56, height: 56)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(DesignTokens.accentColor)
                    } else if let pendingAvatar = pendingAvatar {
                        Image(uiImage: pendingAvatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } else if let avatarUrl = avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            DefaultAvatarView(size: 56)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        DefaultAvatarView(size: 56)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? borderColor : Color.clear, lineWidth: 1.5)
                )

                // 名称和副标题
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Spacer()

                // 箭头指示器
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    VStack {
        PostAsSelectionPanel(
            selectedType: .constant(.primary),
            primaryAccount: nil,
            aliasAccounts: [],
            currentUser: nil
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
