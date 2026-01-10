import SwiftUI

// MARK: - Layout Configuration
struct ProfileNavBarLayout {
    // ==================== 整体布局 ====================
    var horizontalPadding: CGFloat = 16      // 左右边距
    var barHeight: CGFloat = 48              // 导航栏高度
    
    // ==================== 左侧用户名区域 ====================
    var usernameFontSize: CGFloat = 16       // 用户名字体大小
    var chevronFontSize: CGFloat = 12        // 箭头字体大小
    var chevronSize: CGFloat = 24            // 下拉箭头容器大小
    var usernameChevronSpacing: CGFloat = 4  // 用户名和箭头间距
    
    // ==================== 右侧图标区域 ====================
    var iconSize: CGFloat = 22               // 图标大小
    var iconTapArea: CGFloat = 40            // 图标点击区域
    var iconContainerSize: CGFloat = 48      // 图标容器大小
    
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
    var onSettingsTapped: () -> Void = {}
    var onUsernameTapped: () -> Void = {}

    var body: some View {
        HStack {
            // MARK: - 左侧：用户名带下拉箭头
            Button(action: onUsernameTapped) {
                HStack(spacing: layout.usernameChevronSpacing.s) {
                    Text(username)
                        .font(.custom("SFProDisplay-Regular", size: layout.usernameFontSize.f).weight(.semibold))
                        .foregroundColor(layout.textColor)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: layout.chevronFontSize.f))
                        .foregroundColor(layout.textColor)
                        .frame(width: layout.chevronSize.s, height: layout.chevronSize.s)
                }
            }
            
            Spacer()
            
            // MARK: - 右侧：分享和设置图标
            HStack(spacing: 0) {
                Button(action: onShareTapped) {
                    Image("share")
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.iconSize.s, height: layout.iconSize.s)
                        .frame(width: layout.iconTapArea.s, height: layout.iconTapArea.s)
                }
                .frame(width: layout.iconContainerSize.s, height: layout.iconContainerSize.s)
                
                Button(action: onSettingsTapped) {
                    Image("Setting(white)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.iconSize.s, height: layout.iconSize.s)
                        .frame(width: layout.iconTapArea.s, height: layout.iconTapArea.s)
                }
                .frame(width: layout.iconContainerSize.s, height: layout.iconContainerSize.s)
            }
        }
        .padding(.horizontal, layout.horizontalPadding.w)
        .frame(height: layout.barHeight.h)
    }
}

// MARK: - Previews

#Preview("ProfileNavBar - Default") {
    ZStack {
        LinearGradient(
            colors: [.purple.opacity(0.6), .pink.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack(spacing: 0) {
            ProfileTopNavigationBar(
                username: "Jack",
                onShareTapped: { print("Share tapped") },
                onSettingsTapped: { print("Settings tapped") },
                onUsernameTapped: { print("Username tapped") }
            )
            
            Spacer()
        }
    }
}

#Preview("ProfileNavBar - With SafeArea") {
    ZStack {
        LinearGradient(
            colors: [.purple.opacity(0.6), .pink.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack(spacing: 0) {
            ProfileTopNavigationBar(
                username: "Bruce Li",
                onShareTapped: { print("Share tapped") },
                onSettingsTapped: { print("Settings tapped") },
                onUsernameTapped: { print("Username tapped") }
            )
            .padding(.top, 47.h) // 模拟安全区域
            
            Spacer()
        }
    }
}
