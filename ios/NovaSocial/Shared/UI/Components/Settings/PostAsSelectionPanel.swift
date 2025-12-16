import SwiftUI

// 发帖身份类型
enum PostAsType {
    case realName
    case alias
}

struct PostAsSelectionPanel: View {
    @Binding var selectedType: PostAsType
    let realName: String
    let username: String
    let avatarUrl: String?
    var onRealNameTap: (() -> Void)? = nil
    var onAliasTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 真名选项
            PostAsOptionRow(
                avatarUrl: avatarUrl,
                displayName: realName,
                subtitle: username,
                isSelected: selectedType == .realName,
                borderColor: Color(red: 0.82, green: 0.11, blue: 0.26)
            ) {
                onRealNameTap?()
            }

            // 分隔线
            Divider()
                .padding(.leading, 80)

            // 别名选项
            PostAsOptionRow(
                avatarUrl: nil,
                displayName: "Dreamer",
                subtitle: "Alias name",
                isSelected: selectedType == .alias,
                borderColor: Color(red: 0.37, green: 0.37, blue: 0.37)
            ) {
                onAliasTap?()
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // 头像 - 放大到 56x56
                ZStack {
                    if let avatarUrl = avatarUrl, let url = URL(string: avatarUrl) {
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
                        .stroke(borderColor, lineWidth: 1.5)
                )

                // 名称和副标题 - 放大字体
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
            selectedType: .constant(.realName),
            realName: "Bruce Li",
            username: "brucelichina",
            avatarUrl: nil
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
