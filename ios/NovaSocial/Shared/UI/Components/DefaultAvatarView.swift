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

/// 通用头像视图 - 自动显示用户头像或默认头像（支持首字母占位）
struct AvatarView: View {
    let image: UIImage?
    let url: String?
    let size: CGFloat
    var name: String? = nil  // 用戶名（用於顯示首字母占位符）
    var backgroundColor: Color = Color(red: 0.85, green: 0.85, blue: 0.85)

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
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
            } else {
                DefaultAvatarView(size: size, name: name, backgroundColor: backgroundColor)
            }
        }
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
