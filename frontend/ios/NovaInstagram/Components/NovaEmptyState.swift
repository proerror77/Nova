import SwiftUI

// MARK: - Empty State Views

/// Generic empty state view
struct NovaEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var iconColor: Color = DesignColors.textSecondary

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(iconColor)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DesignColors.textPrimary)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(DesignColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let actionTitle = actionTitle, let action = action {
                NovaPrimaryButton(
                    title: actionTitle,
                    action: action,
                    fullWidth: false
                )
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Empty feed state
struct NovaEmptyFeed: View {
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        NovaEmptyState(
            icon: "photo.on.rectangle.angled",
            title: "暫無貼文",
            message: "關注更多用戶以查看他們的貼文",
            actionTitle: onRefresh != nil ? "刷新" : nil,
            action: onRefresh,
            iconColor: DesignColors.brandPrimary
        )
    }
}

/// Empty search results
struct NovaEmptySearch: View {
    let searchQuery: String

    var body: some View {
        NovaEmptyState(
            icon: "magnifyingglass",
            title: "未找到結果",
            message: "嘗試搜索其他內容或檢查拼寫",
            iconColor: DesignColors.textSecondary
        )
    }
}

/// Empty notifications
struct NovaEmptyNotifications: View {
    var body: some View {
        NovaEmptyState(
            icon: "bell.slash",
            title: "暫無通知",
            message: "當有人讚您的貼文或關注您時，通知會顯示在這裡",
            iconColor: DesignColors.textSecondary
        )
    }
}

/// Empty following list
struct NovaEmptyFollowing: View {
    var onFindPeople: (() -> Void)? = nil

    var body: some View {
        NovaEmptyState(
            icon: "person.2",
            title: "尚未關注任何人",
            message: "發現並關注您感興趣的人",
            actionTitle: onFindPeople != nil ? "發現用戶" : nil,
            action: onFindPeople,
            iconColor: DesignColors.brandPrimary
        )
    }
}

/// Empty saved posts
struct NovaEmptySaved: View {
    var body: some View {
        NovaEmptyState(
            icon: "bookmark",
            title: "暫無保存",
            message: "保存您喜歡的貼文以便日後查看",
            iconColor: DesignColors.brandPrimary
        )
    }
}

/// No internet connection
struct NovaNoConnection: View {
    var onRetry: () -> Void

    var body: some View {
        NovaEmptyState(
            icon: "wifi.slash",
            title: "無網絡連接",
            message: "請檢查您的網絡連接並重試",
            actionTitle: "重試",
            action: onRetry,
            iconColor: .orange
        )
    }
}

// MARK: - Error States

/// Generic error state
struct NovaErrorState: View {
    let error: Error
    var onRetry: (() -> Void)? = nil

    var body: some View {
        NovaEmptyState(
            icon: "exclamationmark.triangle",
            title: "發生錯誤",
            message: error.localizedDescription,
            actionTitle: onRetry != nil ? "重試" : nil,
            action: onRetry,
            iconColor: .red
        )
    }
}

/// Permission denied state
struct NovaPermissionDenied: View {
    let permissionType: String
    var onSettings: () -> Void

    var body: some View {
        NovaEmptyState(
            icon: "lock.shield",
            title: "需要權限",
            message: "此功能需要訪問您的\(permissionType)。請在設置中啟用。",
            actionTitle: "前往設置",
            action: onSettings,
            iconColor: .orange
        )
    }
}

// MARK: - Inline Empty States

/// Small inline empty message
struct NovaInlineEmpty: View {
    let message: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(DesignColors.textSecondary)
            }

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(DesignColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Preview

#if DEBUG
struct NovaEmptyState_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            NovaEmptyFeed(onRefresh: {})
                .tabItem { Label("Feed", systemImage: "house") }

            NovaEmptySearch(searchQuery: "iOS")
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NovaEmptyNotifications()
                .tabItem { Label("Notifications", systemImage: "bell") }

            NovaEmptyFollowing(onFindPeople: {})
                .tabItem { Label("Following", systemImage: "person.2") }

            NovaEmptySaved()
                .tabItem { Label("Saved", systemImage: "bookmark") }

            NovaNoConnection(onRetry: {})
                .tabItem { Label("No Connection", systemImage: "wifi.slash") }

            NovaErrorState(
                error: NSError(domain: "", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "網絡請求失敗"
                ]),
                onRetry: {}
            )
            .tabItem { Label("Error", systemImage: "exclamationmark.triangle") }

            NovaPermissionDenied(
                permissionType: "相機",
                onSettings: {}
            )
            .tabItem { Label("Permission", systemImage: "lock.shield") }
        }
        .background(DesignColors.surfaceLight)
    }
}
#endif
