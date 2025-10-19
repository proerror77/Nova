import SwiftUI

// MARK: - Avatar Components

/// Basic circular avatar
struct NovaAvatar: View {
    let emoji: String
    var size: CGFloat = 44
    var backgroundColor: Color? = nil
    var borderColor: Color? = nil
    var borderWidth: CGFloat = 0

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.6))
            .frame(width: size, height: size)
            .background(
                backgroundColor ?? DesignColors.brandPrimary.opacity(0.1)
            )
            .overlay(
                Circle()
                    .strokeBorder(borderColor ?? .clear, lineWidth: borderWidth)
            )
            .clipShape(Circle())
    }
}

/// Avatar with online status indicator
struct NovaAvatarWithStatus: View {
    let emoji: String
    var size: CGFloat = 44
    var isOnline: Bool = false
    var backgroundColor: Color? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NovaAvatar(emoji: emoji, size: size, backgroundColor: backgroundColor)

            if isOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white, lineWidth: size * 0.05)
                    )
            }
        }
    }
}

/// Avatar with badge (notification count)
struct NovaAvatarWithBadge: View {
    let emoji: String
    var size: CGFloat = 44
    var badgeCount: Int = 0
    var backgroundColor: Color? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NovaAvatar(emoji: emoji, size: size, backgroundColor: backgroundColor)

            if badgeCount > 0 {
                Text("\(badgeCount > 99 ? "99+" : String(badgeCount))")
                    .font(.system(size: size * 0.25, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, size * 0.15)
                    .padding(.vertical, size * 0.1)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: size * 0.15, y: -size * 0.1)
            }
        }
    }
}

/// Story-style avatar with gradient ring
struct NovaStoryAvatar: View {
    let emoji: String
    var size: CGFloat = 70
    var hasNewStory: Bool = false
    var isSeen: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                // Gradient ring for new stories
                if hasNewStory {
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: isSeen ?
                                    [Color.gray.opacity(0.3), Color.gray.opacity(0.3)] :
                                    [DesignColors.brandPrimary, DesignColors.brandAccent]
                                ),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: size + 6, height: size + 6)
                }

                // Avatar
                NovaAvatar(
                    emoji: emoji,
                    size: size,
                    backgroundColor: DesignColors.surfaceElevated,
                    borderColor: .white,
                    borderWidth: 3
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Avatar group (overlapping avatars)
struct NovaAvatarGroup: View {
    let emojis: [String]
    var size: CGFloat = 32
    var maxDisplay: Int = 3
    var spacing: CGFloat = -8

    var displayEmojis: [String] {
        Array(emojis.prefix(maxDisplay))
    }

    var remainingCount: Int {
        max(0, emojis.count - maxDisplay)
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(displayEmojis.enumerated()), id: \.offset) { index, emoji in
                NovaAvatar(
                    emoji: emoji,
                    size: size,
                    borderColor: .white,
                    borderWidth: 2
                )
                .zIndex(Double(displayEmojis.count - index))
            }

            if remainingCount > 0 {
                ZStack {
                    Circle()
                        .fill(DesignColors.textSecondary.opacity(0.2))

                    Text("+\(remainingCount)")
                        .font(.system(size: size * 0.35, weight: .semibold))
                        .foregroundColor(DesignColors.textPrimary)
                }
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                )
            }
        }
    }
}

/// Editable avatar with camera icon
struct NovaEditableAvatar: View {
    let emoji: String
    var size: CGFloat = 100
    var onEdit: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NovaAvatar(emoji: emoji, size: size)

            Button(action: onEdit) {
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.2))
                    .foregroundColor(.white)
                    .frame(width: size * 0.35, height: size * 0.35)
                    .background(DesignColors.brandPrimary)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2)
                    )
            }
            .offset(x: size * 0.05, y: size * 0.05)
        }
    }
}

/// Size presets for consistent sizing
extension NovaAvatar {
    enum Size {
        case tiny, small, medium, large, xlarge

        var value: CGFloat {
            switch self {
            case .tiny: return 24
            case .small: return 32
            case .medium: return 44
            case .large: return 64
            case .xlarge: return 100
            }
        }
    }

    static func sized(_ size: Size, emoji: String) -> NovaAvatar {
        NovaAvatar(emoji: emoji, size: size.value)
    }
}

// MARK: - Preview

#if DEBUG
struct NovaAvatar_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Basic avatars
                VStack(spacing: 16) {
                    Text("基础头像")
                        .font(.headline)

                    HStack(spacing: 16) {
                        NovaAvatar.sized(.tiny, emoji: "👤")
                        NovaAvatar.sized(.small, emoji: "👤")
                        NovaAvatar.sized(.medium, emoji: "👤")
                        NovaAvatar.sized(.large, emoji: "👤")
                        NovaAvatar.sized(.xlarge, emoji: "👤")
                    }
                }

                // Avatar with status
                VStack(spacing: 16) {
                    Text("在线状态")
                        .font(.headline)

                    HStack(spacing: 24) {
                        NovaAvatarWithStatus(emoji: "😊", size: 64, isOnline: true)
                        NovaAvatarWithStatus(emoji: "🎨", size: 64, isOnline: false)
                    }
                }

                // Avatar with badge
                VStack(spacing: 16) {
                    Text("消息徽章")
                        .font(.headline)

                    HStack(spacing: 24) {
                        NovaAvatarWithBadge(emoji: "📱", size: 64, badgeCount: 5)
                        NovaAvatarWithBadge(emoji: "💬", size: 64, badgeCount: 99)
                        NovaAvatarWithBadge(emoji: "🔔", size: 64, badgeCount: 150)
                    }
                }

                // Story avatars
                VStack(spacing: 16) {
                    Text("Story 头像")
                        .font(.headline)

                    HStack(spacing: 20) {
                        NovaStoryAvatar(emoji: "🎨", hasNewStory: true, isSeen: false)
                        NovaStoryAvatar(emoji: "📸", hasNewStory: true, isSeen: true)
                        NovaStoryAvatar(emoji: "🌅", hasNewStory: false)
                    }
                }

                // Avatar groups
                VStack(spacing: 16) {
                    Text("头像组")
                        .font(.headline)

                    VStack(spacing: 12) {
                        NovaAvatarGroup(emojis: ["👤", "😊", "🎨"])
                        NovaAvatarGroup(emojis: ["📱", "💬", "🔔", "📸", "🌅"], maxDisplay: 3)
                        NovaAvatarGroup(emojis: ["🎨", "📸", "🌅", "☕️", "🎬", "📱"], size: 40)
                    }
                }

                // Editable avatar
                VStack(spacing: 16) {
                    Text("可编辑头像")
                        .font(.headline)

                    NovaEditableAvatar(emoji: "👤", size: 120, onEdit: {})
                }

                // Different background colors
                VStack(spacing: 16) {
                    Text("自定义背景色")
                        .font(.headline)

                    HStack(spacing: 16) {
                        NovaAvatar(
                            emoji: "🎨",
                            size: 64,
                            backgroundColor: Color.red.opacity(0.2)
                        )
                        NovaAvatar(
                            emoji: "📱",
                            size: 64,
                            backgroundColor: Color.blue.opacity(0.2)
                        )
                        NovaAvatar(
                            emoji: "🌅",
                            size: 64,
                            backgroundColor: Color.orange.opacity(0.2)
                        )
                    }
                }
            }
            .padding()
        }
        .background(DesignColors.surfaceLight)
    }
}
#endif
