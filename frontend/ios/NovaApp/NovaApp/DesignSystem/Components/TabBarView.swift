import SwiftUI

/// Custom Tab Bar with smooth animations
struct CustomTabBar: View {
    @Binding var selectedTab: TabItem
    let tabs: [TabItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    onTap: {
                        withAnimation(.quickSpring) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Theme.Colors.surface
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }
}

struct TabBarButton: View {
    let tab: TabItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: Theme.IconSize.md))
                    .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
                    .scaleEffect(isSelected ? 1.1 : 1.0)

                Text(tab.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum TabItem: Hashable {
    case feed
    case search
    case create
    case notifications
    case profile

    var title: String {
        switch self {
        case .feed: return "Home"
        case .search: return "Search"
        case .create: return "Create"
        case .notifications: return "Notifications"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "house"
        case .search: return "magnifyingglass"
        case .create: return "plus.square"
        case .notifications: return "bell"
        case .profile: return "person.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .feed: return "house.fill"
        case .search: return "magnifyingglass"
        case .create: return "plus.square.fill"
        case .notifications: return "bell.fill"
        case .profile: return "person.circle.fill"
        }
    }
}

#Preview {
    VStack {
        Spacer()
        CustomTabBar(
            selectedTab: .constant(.feed),
            tabs: [.feed, .search, .create, .notifications, .profile]
        )
    }
}
