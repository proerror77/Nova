import SwiftUI

// MARK: - Layout Configuration
struct ProfileUserInfoLayout {
    // ==================== 整体容器 ====================
    var containerWidth: CGFloat
    var verticalSpacing: CGFloat
    var bottomPadding: CGFloat
    var containerVerticalOffset: CGFloat

    // ==================== 头像区域 ====================
    var avatarOuterSize: CGFloat
    var avatarInnerSize: CGFloat
    var avatarBorderWidth: CGFloat
    var avatarBorderColor: Color

    // ==================== 用户名区域 ====================
    var usernameFontSize: CGFloat
    var usernameSpacingFromAvatar: CGFloat

    // ==================== 位置信息 ====================
    var locationFontSize: CGFloat
    var locationSpacing: CGFloat

    // ==================== 职业/身份信息（带蓝标） ====================
    var professionFontSize: CGFloat
    var blueVIconSize: CGFloat
    var professionIconSpacing: CGFloat
    var professionSpacing: CGFloat

    // ==================== 统计数据区域 ====================
    var statsTopPadding: CGFloat
    var statsHorizontalPadding: CGFloat
    var statsLabelFontSize: CGFloat
    var statsValueFontSize: CGFloat
    var statsItemWidth: CGFloat
    var statsItemSpacing: CGFloat
    var statsDividerHeight: CGFloat
    var statsDividerWidth: CGFloat

    // ==================== 颜色 ====================
    var textColor: Color
    var secondaryTextColor: Color

    init(
        containerWidth: CGFloat = 365,
        verticalSpacing: CGFloat = 7,
        bottomPadding: CGFloat = 10,
        containerVerticalOffset: CGFloat = 0,
        avatarOuterSize: CGFloat = 108,
        avatarInnerSize: CGFloat = 100,
        avatarBorderWidth: CGFloat = 1,
        avatarBorderColor: Color = .white,
        usernameFontSize: CGFloat = 20,
        usernameSpacingFromAvatar: CGFloat = 9,
        locationFontSize: CGFloat = 12,
        locationSpacing: CGFloat = 4,
        professionFontSize: CGFloat = 12,
        blueVIconSize: CGFloat = 20,
        professionIconSpacing: CGFloat = 10,
        professionSpacing: CGFloat = 7,
        statsTopPadding: CGFloat = 16,
        statsHorizontalPadding: CGFloat = 40,
        statsLabelFontSize: CGFloat = 16,
        statsValueFontSize: CGFloat = 16,
        statsItemWidth: CGFloat = 132,
        statsItemSpacing: CGFloat = -16,
        statsDividerHeight: CGFloat = 24,
        statsDividerWidth: CGFloat = 1,
        textColor: Color = .white,
        secondaryTextColor: Color = Color(red: 0.97, green: 0.97, blue: 0.97)
    ) {
        self.containerWidth = containerWidth
        self.verticalSpacing = verticalSpacing
        self.bottomPadding = bottomPadding
        self.containerVerticalOffset = containerVerticalOffset
        self.avatarOuterSize = avatarOuterSize
        self.avatarInnerSize = avatarInnerSize
        self.avatarBorderWidth = avatarBorderWidth
        self.avatarBorderColor = avatarBorderColor
        self.usernameFontSize = usernameFontSize
        self.usernameSpacingFromAvatar = usernameSpacingFromAvatar
        self.locationFontSize = locationFontSize
        self.locationSpacing = locationSpacing
        self.professionFontSize = professionFontSize
        self.blueVIconSize = blueVIconSize
        self.professionIconSpacing = professionIconSpacing
        self.professionSpacing = professionSpacing
        self.statsTopPadding = statsTopPadding
        self.statsHorizontalPadding = statsHorizontalPadding
        self.statsLabelFontSize = statsLabelFontSize
        self.statsValueFontSize = statsValueFontSize
        self.statsItemWidth = statsItemWidth
        self.statsItemSpacing = statsItemSpacing
        self.statsDividerHeight = statsDividerHeight
        self.statsDividerWidth = statsDividerWidth
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
    }

    static let `default` = ProfileUserInfoLayout()
}

// MARK: - User Info Section Component
struct ProfileUserInfoSection: View {
    // Data
    let avatarImage: UIImage?
    let avatarUrl: String?
    let username: String?           // 可选，未填写时显示 "User"
    let location: String?           // 可选，未填写时不显示
    let profession: String?         // 可选，未填写时不显示
    let isVerified: Bool
    let followingCount: Int
    let followersCount: Int
    let likesCount: Int

    // Layout configuration
    var layout: ProfileUserInfoLayout = .default

    // 点击回调
    var onFollowingTapped: (() -> Void)?
    var onFollowersTapped: (() -> Void)?

    // 计算显示的用户名（未填写时显示默认值）
    private var displayUsername: String {
        if let name = username, !name.isEmpty {
            return name
        }
        return "User"  // iOS 默认状态
    }

    // 计算显示的位置（未填写时显示占位符）
    private var displayLocation: String {
        if let loc = location, !loc.isEmpty {
            return loc
        }
        return "Add Location"  // iOS 风格占位符
    }

    // 计算显示的职业（未填写时显示占位符）
    private var displayProfession: String {
        if let prof = profession, !prof.isEmpty {
            return prof
        }
        return "Add Profession"  // iOS 风格占位符
    }

    // 判断位置是否已设置
    private var hasLocation: Bool {
        if let loc = location, !loc.isEmpty {
            return true
        }
        return false
    }

    // 判断职业是否已设置
    private var hasProfession: Bool {
        if let prof = profession, !prof.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: layout.verticalSpacing) {
            // MARK: - 头像 + 用户名 + 位置
            VStack(spacing: layout.usernameSpacingFromAvatar) {
                // 头像
                avatarView
                    .frame(width: layout.avatarOuterSize, height: layout.avatarOuterSize)

                // 用户名（始终显示，未填写时显示 "User"）
                Text(displayUsername)
                    .font(.system(size: layout.usernameFontSize, weight: .bold))
                    .lineSpacing(19)
                    .foregroundColor(layout.textColor)

                // 位置信息（始终显示，未填写时显示占位符）
                Text(displayLocation)
                    .font(.system(size: layout.locationFontSize))
                    .lineSpacing(19)
                    .foregroundColor(hasLocation ? layout.textColor : layout.textColor.opacity(0.5))
            }

            // MARK: - 职业/身份信息 - 始终显示，未填写时显示占位符
            HStack(spacing: layout.professionIconSpacing) {
                // 蓝标认证图标（仅在已设置职业时显示）
                if hasProfession {
                    Image("Blue-v")
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.blueVIconSize, height: layout.blueVIconSize)
                }

                Text(displayProfession)
                    .font(.system(size: layout.professionFontSize, weight: .light))
                    .lineSpacing(19)
                    .foregroundColor(hasProfession ? layout.secondaryTextColor : layout.secondaryTextColor.opacity(0.5))
            }
            .padding(.top, layout.professionSpacing)  // ← 单独调整职业栏垂直位置

            // MARK: - 统计数据（Following / Followers / Likes）
            HStack(spacing: layout.statsItemSpacing) {
                // Following - 可点击
                statsItem(label: "Following", value: "\(followingCount)")
                    .frame(width: layout.statsItemWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onFollowingTapped?()
                    }

                // 分隔线
                Rectangle()
                    .fill(layout.textColor)
                    .frame(width: layout.statsDividerWidth, height: layout.statsDividerHeight)

                // Followers - 可点击
                statsItem(label: "Followers", value: "\(followersCount)")
                    .frame(width: layout.statsItemWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onFollowersTapped?()
                    }

                // 分隔线
                Rectangle()
                    .fill(layout.textColor)
                    .frame(width: layout.statsDividerWidth, height: layout.statsDividerHeight)

                // Likes
                statsItem(label: "Likes", value: "\(likesCount)")
                    .frame(width: layout.statsItemWidth)
            }
            .padding(.top, layout.statsTopPadding)
        }
        .frame(width: layout.containerWidth)
        .padding(.bottom, layout.bottomPadding)
        .offset(y: layout.containerVerticalOffset)  // ← 单独调整整个用户信息区域的垂直位置
    }

    // MARK: - Avatar View
    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            // 外圈边框
            Ellipse()
                .foregroundColor(.clear)
                .frame(width: layout.avatarOuterSize, height: layout.avatarOuterSize)
                .overlay(
                    Ellipse()
                        .inset(by: layout.avatarBorderWidth)
                        .stroke(layout.avatarBorderColor, lineWidth: layout.avatarBorderWidth)
                )

            // 头像图片 - 使用统一的默认头像
            if let image = avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: layout.avatarInnerSize, height: layout.avatarInnerSize)
                    .clipShape(Ellipse())
            } else if let urlString = avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        DefaultAvatarView(size: layout.avatarInnerSize)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        DefaultAvatarView(size: layout.avatarInnerSize)
                    }
                }
                .frame(width: layout.avatarInnerSize, height: layout.avatarInnerSize)
                .clipShape(Ellipse())
            } else {
                // 默认头像
                DefaultAvatarView(size: layout.avatarInnerSize)
            }
        }
    }

    // MARK: - Stats Item
    private func statsItem(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 1) {
            Text(LocalizedStringKey(label))
                .font(.system(size: layout.statsLabelFontSize))
                .lineSpacing(19)
                .foregroundColor(layout.textColor)

            Text(value)
                .font(.system(size: layout.statsValueFontSize))
                .lineSpacing(19)
                .foregroundColor(layout.textColor)
        }
    }
}

// MARK: - Previews

#Preview("UserInfo - Default") {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        ProfileUserInfoSection(
            avatarImage: nil,
            avatarUrl: nil,
            username: "Bruce Li",
            location: "China",
            profession: "Illustrator / Junior Illustrator",
            isVerified: true,
            followingCount: 592,
            followersCount: 1449,
            likesCount: 452,
            layout: ProfileUserInfoLayout(
                containerWidth: 365,
                avatarOuterSize: 108,
                avatarInnerSize: 100
            )
        )
    }
}

#Preview("UserInfo - Dark Mode") {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        ProfileUserInfoSection(
            avatarImage: nil,
            avatarUrl: nil,
            username: "Bruce Li",
            location: "China",
            profession: "Illustrator / Junior Illustrator",
            isVerified: true,
            followingCount: 592,
            followersCount: 1449,
            likesCount: 452,
            layout: ProfileUserInfoLayout(
                containerWidth: 365,
                avatarOuterSize: 108,
                avatarInnerSize: 100
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("UserInfo - Empty") {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        ProfileUserInfoSection(
            avatarImage: nil,
            avatarUrl: nil,
            username: nil,           // 未填写 -> 显示 "User"
            location: nil,           // 未填写 -> 不显示
            profession: nil,         // 未填写 -> 不显示
            isVerified: false,
            followingCount: 0,
            followersCount: 0,
            likesCount: 0,
            layout: ProfileUserInfoLayout(
                containerWidth: 365,
                avatarOuterSize: 108,
                avatarInnerSize: 100
            )
        )
    }
}

#Preview("UserInfo - Empty Dark Mode") {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        ProfileUserInfoSection(
            avatarImage: nil,
            avatarUrl: nil,
            username: nil,
            location: nil,
            profession: nil,
            isVerified: false,
            followingCount: 0,
            followersCount: 0,
            likesCount: 0,
            layout: ProfileUserInfoLayout(
                containerWidth: 365,
                avatarOuterSize: 108,
                avatarInnerSize: 100
            )
        )
    }
    .preferredColorScheme(.dark)
}
