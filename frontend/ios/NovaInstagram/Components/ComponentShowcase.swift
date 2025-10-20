import SwiftUI

// MARK: - Component Showcase Demo

/// Demonstrates all UI components in a single scrollable view
struct ComponentShowcase: View {
    @State private var username = ""
    @State private var password = ""
    @State private var bio = ""
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    buttonSection
                    textFieldSection
                    cardSection
                    loadingStateSection
                    emptyStateSection
                }
                .padding(.vertical, 24)
            }
            .background(DesignColors.surfaceLight)
            .navigationTitle("組件展示")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Button Section

    private var buttonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Buttons 按鈕")

            VStack(spacing: 12) {
                NovaPrimaryButton(
                    title: "主要操作",
                    action: {},
                    icon: "checkmark"
                )

                NovaPrimaryButton(
                    title: "加載中",
                    action: {},
                    isLoading: true
                )

                NovaPrimaryButton(
                    title: "禁用狀態",
                    action: {},
                    isEnabled: false
                )

                NovaSecondaryButton(
                    title: "次要操作",
                    action: {},
                    icon: "heart"
                )

                NovaTextButton(
                    title: "文本按鈕",
                    action: {}
                )

                NovaDestructiveButton(
                    title: "刪除操作",
                    action: {}
                )

                HStack(spacing: 16) {
                    NovaIconButton(icon: "heart", action: {})
                    NovaIconButton(icon: "bookmark", action: {})
                    NovaIconButton(icon: "paperplane", action: {})
                    NovaIconButton(icon: "gear", action: {})
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - TextField Section

    private var textFieldSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Text Fields 輸入框")

            VStack(spacing: 12) {
                NovaTextField(
                    placeholder: "用戶名",
                    text: $username,
                    icon: "person"
                )

                NovaTextField(
                    placeholder: "密碼",
                    text: $password,
                    icon: "lock",
                    isSecure: true
                )

                NovaTextField(
                    placeholder: "錯誤示例",
                    text: .constant("invalid"),
                    icon: "exclamationmark.triangle",
                    errorMessage: "此字段為必填項"
                )

                NovaSearchField(
                    text: $searchText,
                    placeholder: "搜索用戶..."
                )

                NovaTextEditor(
                    placeholder: "分享您的想法...",
                    text: $bio,
                    minHeight: 100
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Card Section

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Cards 卡片")

            NovaCard {
                Text("基本卡片內容")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            NovaUserCard(
                avatar: "👤",
                username: "John Doe",
                subtitle: "iOS 開發者",
                size: 50
            )

            NovaStatsCard(stats: [
                .init(title: "貼文", value: "1,234"),
                .init(title: "粉絲", value: "54.3K"),
                .init(title: "追蹤", value: "2,134")
            ])

            NovaActionCard(
                icon: "gear",
                title: "設置",
                subtitle: "偏好設置和隱私",
                action: {}
            )

            HStack(spacing: 8) {
                NovaImageCard(emoji: "🎨", size: 100)
                NovaImageCard(emoji: "📸", size: 100)
                NovaImageCard(emoji: "🌅", size: 100)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Loading State Section

    private var loadingStateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Loading States 加載狀態")

            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    NovaLoadingSpinner(size: 20)
                    Text("Small")
                        .font(.caption)
                        .foregroundColor(DesignColors.textSecondary)
                }

                VStack(spacing: 8) {
                    NovaLoadingSpinner(size: 32)
                    Text("Medium")
                        .font(.caption)
                        .foregroundColor(DesignColors.textSecondary)
                }

                VStack(spacing: 8) {
                    NovaLoadingSpinner(size: 44)
                    Text("Large")
                        .font(.caption)
                        .foregroundColor(DesignColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                NovaSkeletonBox(width: 200, height: 20)
                NovaSkeletonBox(height: 100)
                HStack(spacing: 8) {
                    NovaSkeletonBox(height: 60)
                    NovaSkeletonBox(height: 60)
                    NovaSkeletonBox(height: 60)
                }
            }

            NovaPullToRefreshIndicator(isRefreshing: true)

            NovaUserListSkeleton()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Empty State Section

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Empty & Error States 空狀態")

            NovaCard {
                NovaInlineEmpty(
                    message: "暫無數據",
                    icon: "tray"
                )
            }

            // Mini empty states for demo
            NovaCard(padding: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundColor(DesignColors.brandPrimary)
                    Text("暫無貼文")
                        .font(.system(size: 16, weight: .semibold))
                    Text("關注用戶以查看內容")
                        .font(.system(size: 13))
                        .foregroundColor(DesignColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }

            NovaCard(padding: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text("發生錯誤")
                        .font(.system(size: 16, weight: .semibold))
                    NovaPrimaryButton(
                        title: "重試",
                        action: {},
                        fullWidth: false
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helper

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(DesignColors.textPrimary)
    }
}

// MARK: - Preview

#if DEBUG
struct ComponentShowcase_Previews: PreviewProvider {
    static var previews: some View {
        ComponentShowcase()
    }
}
#endif
