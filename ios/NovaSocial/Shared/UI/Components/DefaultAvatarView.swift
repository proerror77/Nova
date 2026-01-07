import SwiftUI

/// 默认头像视图 - 在用户未设置头像时显示用戶名首字母或默认图标
struct DefaultAvatarView: View {
    let size: CGFloat
    var name: String? = nil  // 用戶名（用於顯示首字母）
    var backgroundColor: Color = Color(red: 0.85, green: 0.85, blue: 0.85)
    var iconColor: Color = Color(red: 0.6, green: 0.6, blue: 0.6)
    var textColor: Color = .white

    /// 從用戶名提取首字母（支持中英文）
    private var initials: String {
        guard let name = name, !name.isEmpty else { return "" }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return ""
    }
    
    /// 根據名字生成背景顏色
    private var nameBasedColor: Color {
        guard let name = name, !name.isEmpty else { return backgroundColor }
        let colors: [Color] = [
            Color(red: 0.82, green: 0.11, blue: 0.26),  // 紅色
            Color(red: 0.20, green: 0.60, blue: 0.86),  // 藍色
            Color(red: 0.30, green: 0.69, blue: 0.31),  // 綠色
            Color(red: 0.61, green: 0.35, blue: 0.71),  // 紫色
            Color(red: 1.00, green: 0.60, blue: 0.00),  // 橙色
            Color(red: 0.00, green: 0.74, blue: 0.83),  // 青色
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(initials.isEmpty ? backgroundColor : nameBasedColor)
                .frame(width: size, height: size)

            if initials.isEmpty {
                // 沒有名字時顯示默認圖標
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.5, height: size * 0.5)
                    .foregroundColor(iconColor)
                    .offset(y: size * 0.05)
            } else {
                // 有名字時顯示首字母
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(textColor)
            }
        }
        .clipShape(Circle())
    }
}

/// Account type for avatar border color indication
/// Issue #259: Red border = Real Name (primary), Gray border = Alias
enum AccountType: String {
    case primary = "primary"  // Real name account - Red border
    case alias = "alias"      // Alias/pseudonym - Gray border

    /// Border color for this account type
    var borderColor: Color {
        switch self {
        case .primary:
            return Color(red: 0.82, green: 0.11, blue: 0.26)  // Red (#D11C42)
        case .alias:
            return Color(red: 0.6, green: 0.6, blue: 0.6)     // Gray
        }
    }

    /// Initialize from optional string (defaults to primary)
    init(from string: String?) {
        if let str = string, let type = AccountType(rawValue: str) {
            self = type
        } else {
            self = .primary
        }
    }
}

/// 通用头像视图 - 自动显示用户头像或默认头像（支持首字母占位）
/// Issue #259: Supports colored border indicating account type
struct AvatarView: View {
    let image: UIImage?
    let url: String?
    let size: CGFloat
    var name: String? = nil  // 用戶名（用於顯示首字母占位符）
    var backgroundColor: Color = Color(red: 0.85, green: 0.85, blue: 0.85)
    /// Account type for border color: "primary" (red) or "alias" (gray)
    var accountType: String? = nil
    /// Whether to show the account type border
    var showBorder: Bool = true

    /// Border width scales with avatar size
    private var borderWidth: CGFloat {
        max(2, size * 0.05)  // 5% of size, minimum 2pt
    }

    /// Computed border color based on account type
    private var borderColor: Color {
        guard showBorder, accountType != nil else { return .clear }
        return AccountType(from: accountType).borderColor
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: borderWidth)
                    )
            } else if let urlString = url, !urlString.isEmpty, let url = URL(string: urlString) {
                // 使用 CachedAsyncImage 替代 AsyncImage 以获得磁盘缓存和更好的性能
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: size * 2, height: size * 2),  // 2x for Retina
                    enableProgressiveLoading: false,  // 头像不需要渐进式加载
                    priority: .high
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    DefaultAvatarView(size: size, name: name, backgroundColor: backgroundColor)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: borderWidth)
                )
            } else {
                DefaultAvatarView(size: size, name: name, backgroundColor: backgroundColor)
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: borderWidth)
                    )
            }
        }
    }
}

// MARK: - Stacked Avatar View (for group chats)

/// 堆疊頭像視圖 - 用於群組聊天顯示多個成員頭像
struct StackedAvatarView: View {
    let avatarUrls: [String?]  // 成員頭像URLs (最多顯示3個)
    let names: [String]        // 成員名稱 (用於顯示首字母占位符)
    let size: CGFloat          // 主要頭像大小

    /// 小頭像的縮放比例
    private let smallScale: CGFloat = 0.6

    /// 計算偏移量
    private var offset: CGFloat {
        size * 0.35
    }

    var body: some View {
        let displayCount = min(avatarUrls.count, 3)
        let smallSize = size * smallScale

        ZStack {
            // 根據成員數量顯示不同佈局
            if displayCount >= 3 {
                // 3個頭像：右下、左下、上中
                AvatarView(
                    image: nil,
                    url: avatarUrls.indices.contains(2) ? avatarUrls[2] : nil,
                    size: smallSize,
                    name: names.indices.contains(2) ? names[2] : nil
                )
                .offset(x: offset * 0.5, y: offset * 0.5)

                AvatarView(
                    image: nil,
                    url: avatarUrls.indices.contains(1) ? avatarUrls[1] : nil,
                    size: smallSize,
                    name: names.indices.contains(1) ? names[1] : nil
                )
                .offset(x: -offset * 0.5, y: offset * 0.5)

                AvatarView(
                    image: nil,
                    url: avatarUrls.indices.contains(0) ? avatarUrls[0] : nil,
                    size: smallSize,
                    name: names.indices.contains(0) ? names[0] : nil
                )
                .offset(x: 0, y: -offset * 0.3)
            } else if displayCount == 2 {
                // 2個頭像：右下、左上
                AvatarView(
                    image: nil,
                    url: avatarUrls.indices.contains(1) ? avatarUrls[1] : nil,
                    size: smallSize,
                    name: names.indices.contains(1) ? names[1] : nil
                )
                .offset(x: offset * 0.4, y: offset * 0.4)

                AvatarView(
                    image: nil,
                    url: avatarUrls.indices.contains(0) ? avatarUrls[0] : nil,
                    size: smallSize,
                    name: names.indices.contains(0) ? names[0] : nil
                )
                .offset(x: -offset * 0.4, y: -offset * 0.4)
            } else if displayCount == 1 {
                // 只有1個頭像：顯示單個
                AvatarView(
                    image: nil,
                    url: avatarUrls.first ?? nil,
                    size: size,
                    name: names.first
                )
            } else {
                // 沒有頭像：顯示群組圖標
                DefaultGroupAvatarView(size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 默認群組頭像視圖 - 無成員時顯示
struct DefaultGroupAvatarView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.20, green: 0.60, blue: 0.86))  // 藍色背景
                .frame(width: size, height: size)

            Image(systemName: "person.2.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundColor(.white)
        }
        .clipShape(Circle())
    }
}

// MARK: - Previews

#Preview("Avatar - Default") {
    VStack(spacing: 20) {
        DefaultAvatarView(size: 136)
        DefaultAvatarView(size: 100)
        DefaultAvatarView(size: 60)
        DefaultAvatarView(size: 40)
    }
    .padding()
    .background(Color.black.opacity(0.3))
}

#Preview("Avatar - With Initials") {
    VStack(spacing: 20) {
        DefaultAvatarView(size: 60, name: "Alice")
        DefaultAvatarView(size: 60, name: "Bob")
        DefaultAvatarView(size: 60, name: "Charlie")
        DefaultAvatarView(size: 60, name: "小明")
        DefaultAvatarView(size: 60, name: "田中")
    }
    .padding()
    .background(Color.black.opacity(0.3))
}

#Preview("Avatar - Dark Mode") {
    VStack(spacing: 20) {
        DefaultAvatarView(size: 136)
        DefaultAvatarView(size: 100, name: "User")
        DefaultAvatarView(size: 60, name: "Test")
        DefaultAvatarView(size: 40)
    }
    .padding()
    .background(Color.black.opacity(0.3))
    .preferredColorScheme(.dark)
}

#Preview("AvatarView - No Image") {
    AvatarView(image: nil, url: nil, size: 100)
}

#Preview("AvatarView - With Name") {
    AvatarView(image: nil, url: nil, size: 100, name: "John")
}

#Preview("AvatarView - Dark Mode") {
    AvatarView(image: nil, url: nil, size: 100, name: "Test")
        .preferredColorScheme(.dark)
}

#Preview("AvatarView - Account Type Borders (#259)") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            VStack {
                AvatarView(image: nil, url: nil, size: 60, name: "Alice", accountType: "primary")
                Text("Primary (Red)")
                    .font(.caption)
            }
            VStack {
                AvatarView(image: nil, url: nil, size: 60, name: "Bob", accountType: "alias")
                Text("Alias (Gray)")
                    .font(.caption)
            }
            VStack {
                AvatarView(image: nil, url: nil, size: 60, name: "Charlie", accountType: nil)
                Text("No Type")
                    .font(.caption)
            }
        }
        HStack(spacing: 20) {
            AvatarView(image: nil, url: nil, size: 40, name: "S", accountType: "primary")
            AvatarView(image: nil, url: nil, size: 50, name: "M", accountType: "primary")
            AvatarView(image: nil, url: nil, size: 70, name: "L", accountType: "primary")
        }
    }
    .padding()
    .background(Color.black.opacity(0.3))
}

#Preview("StackedAvatarView - 3 Members") {
    StackedAvatarView(
        avatarUrls: [nil, nil, nil],
        names: ["Alice", "Bob", "Charlie"],
        size: 60
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("StackedAvatarView - 2 Members") {
    StackedAvatarView(
        avatarUrls: [nil, nil],
        names: ["Alice", "Bob"],
        size: 60
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("DefaultGroupAvatarView") {
    DefaultGroupAvatarView(size: 60)
        .padding()
        .background(Color.gray.opacity(0.3))
}
