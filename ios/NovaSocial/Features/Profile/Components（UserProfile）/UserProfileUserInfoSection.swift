import SwiftUI

// MARK: - Layout Configuration
struct UserProfileUserInfoLayout {
    // ==================== 整体位置调整 ====================
    var topPadding: CGFloat = 0               // 顶部边距（与 Profile 一致）
    var bottomPadding: CGFloat = 10           // 底部边距（与 Profile 一致）

    // ==================== 头像区域 ====================
    var avatarOuterSize: CGFloat = 108        // 头像外圈大小
    var avatarInnerSize: CGFloat = 100        // 头像内圈大小
    var avatarBorderWidth: CGFloat = 1        // 头像边框宽度（与 Profile 一致）
    var avatarBorderColor: Color = .white     // 头像边框颜色

    // ==================== 用户名 ====================
    var usernameFontSize: CGFloat = 20        // 用户名字体大小
    var usernameTopPadding: CGFloat = 9       // 用户名顶部间距（与 Profile 一致）

    // ==================== 位置信息 ====================
    var locationFontSize: CGFloat = 12        // 位置字体大小
    var locationTopPadding: CGFloat = 4       // 位置顶部间距

    // ==================== 职业信息 ====================
    var professionFontSize: CGFloat = 12      // 职业字体大小
    var professionTopPadding: CGFloat = 7     // 职业顶部间距（与 Profile 一致）
    var professionOpacity: CGFloat = 0.9      // 职业文字透明度

    // ==================== 统计数据区域 ====================
    var statsTopPadding: CGFloat = 8          // 统计区域顶部间距（与 Profile 一致）
    var statsItemWidth: CGFloat = 132         // 每个统计项宽度（与 Profile 一致）
    var statsFontSize: CGFloat = 16           // 统计数字字体大小
    var statsLabelFontSize: CGFloat = 16      // 统计标签字体大小
    var statsDividerHeight: CGFloat = 24      // 分隔线高度（与 Profile 一致）
    var statsDividerWidth: CGFloat = 1        // 分隔线宽度
    var statsVerticalSpacing: CGFloat = 2     // 标签和数值间距

    // ==================== 颜色 ====================
    var textColor: Color = .white
    var placeholderColor: Color = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)

    static let `default` = UserProfileUserInfoLayout()
}

// MARK: - UserProfile User Info Section Component
struct UserProfileUserInfoSection: View {
    // Data
    var avatarUrl: String?
    var username: String
    var location: String?
    var profession: String?
    var followingCount: Int
    var followersCount: Int
    var likesCount: Int

    // Alias account support
    var isAlias: Bool = false
    var aliasName: String? = nil

    // Layout
    var layout: UserProfileUserInfoLayout = .default

    // Actions
    var onFollowingTapped: () -> Void = {}
    var onFollowersTapped: () -> Void = {}
    var onLikesTapped: () -> Void = {}

    /// Display name - uses aliasName for alias accounts
    private var displayName: String {
        if isAlias, let alias = aliasName {
            return alias
        }
        return username
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // MARK: - 头像
            avatarSection
                .padding(.top, layout.topPadding)

            // MARK: - 用户名
            HStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: layout.usernameFontSize, weight: .bold))
                    .foregroundColor(layout.textColor)

                // Alias badge
                if isAlias {
                    Text("Alias")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.87, green: 0.11, blue: 0.26).opacity(0.8))
                        )
                }
            }
            .padding(.top, layout.usernameTopPadding)

            // MARK: - 位置
            if let location = location, !location.isEmpty {
                Text(location)
                    .font(.system(size: layout.locationFontSize))
                    .foregroundColor(layout.textColor)
                    .padding(.top, layout.locationTopPadding)
            }

            // MARK: - 职业
            if let profession = profession, !profession.isEmpty {
                Text(profession)
                    .font(.system(size: layout.professionFontSize, weight: .light))
                    .foregroundColor(layout.textColor.opacity(layout.professionOpacity))
                    .padding(.top, layout.professionTopPadding)
            }

            // MARK: - 统计数据
            statsSection
                .padding(.top, layout.statsTopPadding)
        }
        .frame(maxWidth: .infinity)  // 确保居中
        .padding(.bottom, layout.bottomPadding)
    }

    // MARK: - Avatar Section
    // 使用 CachedAsyncImage 优化头像加载，支持磁盘缓存
    private var avatarSection: some View {
        ZStack {
            Circle()
                .stroke(layout.avatarBorderColor, lineWidth: layout.avatarBorderWidth)
                .frame(width: layout.avatarOuterSize, height: layout.avatarOuterSize)

            if let urlString = avatarUrl, let url = URL(string: urlString) {
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: layout.avatarInnerSize * 2, height: layout.avatarInnerSize * 2),  // 2x for retina
                    enableProgressiveLoading: false,
                    priority: .high
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle().fill(layout.placeholderColor)
                }
                .frame(width: layout.avatarInnerSize, height: layout.avatarInnerSize)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(layout.placeholderColor)
                    .frame(width: layout.avatarInnerSize, height: layout.avatarInnerSize)
            }
        }
    }

    // MARK: - Stats Section
    // 使用 contentTransition(.numericText()) 实现数字变化动画
    private var statsSection: some View {
        HStack(spacing: 0) {
            // Following
            Button(action: onFollowingTapped) {
                VStack(spacing: layout.statsVerticalSpacing) {
                    Text("Following")
                        .font(.system(size: layout.statsLabelFontSize))
                        .foregroundColor(layout.textColor)
                    Text("\(followingCount)")
                        .font(.system(size: layout.statsFontSize))
                        .foregroundColor(layout.textColor)
                        .contentTransition(.numericText())  // iOS 17+ 数字变化动画
                }
            }
            .frame(width: layout.statsItemWidth)

            // Divider
            Rectangle()
                .fill(layout.textColor)
                .frame(width: layout.statsDividerWidth, height: layout.statsDividerHeight)

            // Followers
            Button(action: onFollowersTapped) {
                VStack(spacing: layout.statsVerticalSpacing) {
                    Text("Followers")
                        .font(.system(size: layout.statsLabelFontSize))
                        .foregroundColor(layout.textColor)
                    Text("\(followersCount)")
                        .font(.system(size: layout.statsFontSize))
                        .foregroundColor(layout.textColor)
                        .contentTransition(.numericText())  // iOS 17+ 数字变化动画
                }
            }
            .frame(width: layout.statsItemWidth)

            // Divider
            Rectangle()
                .fill(layout.textColor)
                .frame(width: layout.statsDividerWidth, height: layout.statsDividerHeight)

            // Likes
            Button(action: onLikesTapped) {
                VStack(spacing: layout.statsVerticalSpacing) {
                    Text("Likes")
                        .font(.system(size: layout.statsLabelFontSize))
                        .foregroundColor(layout.textColor)
                    Text("\(likesCount)")
                        .font(.system(size: layout.statsFontSize))
                        .foregroundColor(layout.textColor)
                        .contentTransition(.numericText())  // iOS 17+ 数字变化动画
                }
            }
            .frame(width: layout.statsItemWidth)
        }
    }
}

// MARK: - Previews

#Preview("UserProfileUserInfo - Default") {
    ZStack {
        Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
            .ignoresSafeArea()

        UserProfileUserInfoSection(
            avatarUrl: nil,
            username: "Juliette",
            location: "England",
            profession: "Artist",
            followingCount: 592,
            followersCount: 1449,
            likesCount: 452
        )
    }
}

#Preview("UserProfileUserInfo - Custom Layout") {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        UserProfileUserInfoSection(
            avatarUrl: nil,
            username: "Juliette",
            location: "England",
            profession: "Artist",
            followingCount: 592,
            followersCount: 1449,
            likesCount: 452,
            layout: UserProfileUserInfoLayout(
                topPadding: 30,
                avatarOuterSize: 120,
                avatarInnerSize: 112,
                usernameFontSize: 24,
                statsFontSize: 18
            )
        )
    }
}
