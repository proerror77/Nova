import SwiftUI

// MARK: - Layout Configuration
struct UserProfileNavBarLayout {
    // ==================== 位置调整 ====================
    var horizontalPadding: CGFloat = 20       // 左右边距（与 Profile 一致）
    var topPadding: CGFloat = 60              // 顶部边距（与 Profile 一致）
    var bottomPadding: CGFloat = 40           // 底部边距（与 Profile 一致）

    // ==================== 左侧返回按钮 ====================
    var backButtonSize: CGFloat = 20          // 返回箭头图标大小
    var backButtonWeight: Font.Weight = .semibold  // 返回箭头粗细
    var backButtonTapAreaSize: CGFloat = 44   // 返回按钮点击区域大小

    // ==================== 右侧分享按钮 ====================
    var shareIconSize: CGFloat = 24           // 分享图标大小

    // ==================== 中间认证徽章 ====================
    var badgeIconSize: CGFloat = 20           // 认证图标大小
    var badgeFontSize: CGFloat = 16           // 认证文字大小
    var badgeSpacing: CGFloat = 8             // 图标和文字间距
    var badgeIconColor: Color = .blue         // 认证图标颜色

    // ==================== 颜色 ====================
    var iconColor: Color = .white

    static let `default` = UserProfileNavBarLayout()
}

// MARK: - UserProfile Top Navigation Bar Component
struct UserProfileTopNavigationBar: View {
    // Data
    var isVerified: Bool = true
    var verifiedText: String = "Verified Icered Partner"

    // Layout
    var layout: UserProfileNavBarLayout = .default

    // Actions
    var onBackTapped: () -> Void = {}
    var onShareTapped: () -> Void = {}

    var body: some View {
        ZStack {
            // MARK: - 中间：认证徽章（居中）
            if isVerified {
                HStack(spacing: layout.badgeSpacing) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: layout.badgeIconSize))
                        .foregroundColor(layout.badgeIconColor)

                    Text(verifiedText)
                        .font(.system(size: layout.badgeFontSize))
                        .foregroundColor(layout.iconColor)
                }
            }

            // MARK: - 左右按钮
            HStack {
                Button(action: onBackTapped) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: layout.backButtonSize, weight: layout.backButtonWeight))
                        .foregroundColor(layout.iconColor)
                        .frame(width: layout.backButtonTapAreaSize, height: layout.backButtonTapAreaSize)
                }

                Spacer()

                Button(action: onShareTapped) {
                    Image("share")
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.shareIconSize, height: layout.shareIconSize)
                }
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.bottomPadding)
    }
}

// MARK: - Previews

#Preview("UserProfileNavBar - Default") {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        VStack {
            UserProfileTopNavigationBar(
                isVerified: true,
                layout: UserProfileNavBarLayout(
                    horizontalPadding: 12,
                    topPadding: 60,
                    bottomPadding: 10
                ),
                onBackTapped: { print("Back tapped") },
                onShareTapped: { print("Share tapped") }
            )

            Spacer()
        }
    }
}

#Preview("UserProfileNavBar - Not Verified") {
    ZStack {
        Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
            .ignoresSafeArea()

        VStack {
            UserProfileTopNavigationBar(
                isVerified: false,
                layout: UserProfileNavBarLayout(
                    horizontalPadding: 20,
                    topPadding: 80,
                    bottomPadding: 20
                ),
                onBackTapped: { print("Back tapped") },
                onShareTapped: { print("Share tapped") }
            )

            Spacer()
        }
    }
}
