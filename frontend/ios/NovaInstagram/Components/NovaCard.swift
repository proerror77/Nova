import SwiftUI

// MARK: - Card Components

/// Basic card container
struct NovaCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 12
    var backgroundColor: Color = DesignColors.surfaceElevated
    var hasShadow: Bool = true

    init(
        padding: CGFloat = 12,
        backgroundColor: Color = DesignColors.surfaceElevated,
        hasShadow: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.backgroundColor = backgroundColor
        self.hasShadow = hasShadow
    }

    var body: some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .cornerRadius(12)
            .if(hasShadow) { view in
                view.shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            }
    }
}

/// User card - displays user info
struct NovaUserCard: View {
    let avatar: String
    let username: String
    let subtitle: String?
    var size: CGFloat = 44
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                Text(avatar)
                    .font(.system(size: size * 0.6))
                    .frame(width: size, height: size)
                    .background(DesignColors.brandPrimary.opacity(0.1))
                    .cornerRadius(size / 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(username)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignColors.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(DesignColors.textSecondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Stats card - displays metrics
struct NovaStatsCard: View {
    struct Stat {
        let title: String
        let value: String
    }

    let stats: [Stat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                VStack(spacing: 6) {
                    Text(stat.value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DesignColors.textPrimary)
                    Text(stat.title)
                        .font(.system(size: 12))
                        .foregroundColor(DesignColors.textSecondary)
                }
                .frame(maxWidth: .infinity)

                if index < stats.count - 1 {
                    Divider()
                        .frame(height: 40)
                }
            }
        }
        .padding(.vertical, 16)
        .background(DesignColors.surfaceElevated)
        .cornerRadius(12)
    }
}

/// Action card - for settings/menu items
struct NovaActionCard: View {
    let icon: String
    let title: String
    let subtitle: String?
    var iconColor: Color = DesignColors.brandPrimary
    var showChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DesignColors.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(DesignColors.textSecondary)
                    }
                }

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignColors.textSecondary)
                }
            }
            .padding(12)
            .background(DesignColors.surfaceElevated)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Image card - for gallery/grid views
struct NovaImageCard: View {
    let emoji: String
    var size: CGFloat = 100
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            Text(emoji)
                .font(.system(size: size * 0.4))
                .frame(width: size, height: size)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            DesignColors.brandPrimary.opacity(0.1),
                            DesignColors.brandAccent.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - View Extension for Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NovaCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                NovaCard {
                    Text("基本卡片內容")
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                NovaUserCard(
                    avatar: "👤",
                    username: "John Doe",
                    subtitle: "2小時前"
                )
                .padding(.horizontal)

                NovaStatsCard(stats: [
                    .init(title: "貼文", value: "1,234"),
                    .init(title: "粉絲", value: "54.3K"),
                    .init(title: "追蹤", value: "2,134")
                ])
                .padding(.horizontal)

                NovaActionCard(
                    icon: "gear",
                    title: "設置",
                    subtitle: "偏好設置和隱私",
                    action: {}
                )
                .padding(.horizontal)

                HStack(spacing: 8) {
                    NovaImageCard(emoji: "🎨")
                    NovaImageCard(emoji: "📸")
                    NovaImageCard(emoji: "🌅")
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(DesignColors.surfaceLight)
    }
}
#endif
