import SwiftUI

// MARK: - Layout Configuration
struct ProfileNavBarLayout {
    // ==================== 位置调整 ====================
    var horizontalPadding: CGFloat = 20      // 左右边距
    var topPadding: CGFloat = 60             // 顶部边距（距离安全区域）
    var bottomPadding: CGFloat = 40          // 底部边距

    // ==================== 左侧用户名区域 ====================
    var usernameFontSize: CGFloat = 20       // 用户名字体大小
    var chevronSize: CGFloat = 12            // 下拉箭头大小
    var usernameChevronSpacing: CGFloat = 6  // 用户名和箭头间距

    // ==================== 右侧图标区域 ====================
    var iconSize: CGFloat = 24               // 图标大小
    var iconSpacing: CGFloat = 18            // 图标之间间距

    // ==================== 颜色 ====================
    var textColor: Color = .white
    var iconColor: Color = .white

    static let `default` = ProfileNavBarLayout()
}

// MARK: - Top Navigation Bar Component
struct ProfileTopNavigationBar: View {
    // Data
    let username: String

    // Layout configuration
    var layout: ProfileNavBarLayout = .default

    // Actions
    var onShareTapped: () -> Void = {}
    var onQRCodeTapped: () -> Void = {}
    var onSettingsTapped: () -> Void = {}
    var onUsernameTapped: () -> Void = {}

    var body: some View {
        HStack {
            // MARK: - 左侧：用户名带下拉箭头
            Button(action: onUsernameTapped) {
                HStack(spacing: layout.usernameChevronSpacing) {
                    Text(username)
                        .font(.system(size: layout.usernameFontSize, weight: .medium))
                        .lineSpacing(19)
                        .foregroundColor(layout.textColor)

                    Image(systemName: "chevron.down")
                        .font(.system(size: layout.chevronSize, weight: .medium))
                        .foregroundColor(layout.textColor)
                }
            }

            Spacer()

            // MARK: - 右侧：二维码、分享和设置图标
            HStack(spacing: layout.iconSpacing) {
                Button(action: onQRCodeTapped) {
                    Image(systemName: "qrcode")
                        .font(.system(size: layout.iconSize - 2, weight: .medium))
                        .foregroundColor(layout.iconColor)
                }

                Button(action: onShareTapped) {
                    Image("share")
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.iconSize, height: layout.iconSize)
                }

                Button(action: onSettingsTapped) {
                    Image("Setting(white)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.iconSize, height: layout.iconSize)
                }
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        VStack {
            ProfileTopNavigationBar(
                username: "Bruce Li",
                layout: ProfileNavBarLayout(
                    horizontalPadding: 20,
                    topPadding: 60,
                    bottomPadding: 40
                ),
                onShareTapped: { print("Share tapped") },
                onSettingsTapped: { print("Settings tapped") }
            )

            Spacer()
        }
    }
}
