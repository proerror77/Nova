import SwiftUI

// MARK: - Layout Configuration
struct ProfileUserInfoLayout {
    // ==================== 整体容器 ====================
    var containerWidth: CGFloat = 365        // 容器宽度
    var verticalSpacing: CGFloat = 7         // 各区域垂直间距
    var bottomPadding: CGFloat = 10          // 底部边距

    // ==================== 头像区域 ====================
    var avatarOuterSize: CGFloat = 108       // 外圈大小
    var avatarInnerSize: CGFloat = 100       // 内圈/头像大小
    var avatarBorderWidth: CGFloat = 1       // 外圈边框宽度
    var avatarBorderColor: Color = .white

    // ==================== 用户名区域 ====================
    var usernameFontSize: CGFloat = 20       // 用户名字体大小
    var usernameSpacingFromAvatar: CGFloat = 9  // 与头像的间距

    // ==================== 位置信息 ====================
    var locationFontSize: CGFloat = 12       // 位置字体大小
    var locationSpacing: CGFloat = 4         // 与用户名的间距

    // ==================== 职业/身份信息（带蓝标） ====================
    var professionFontSize: CGFloat = 12     // 职业字体大小
    var blueVIconSize: CGFloat = 20          // 蓝标图标大小
    var professionIconSpacing: CGFloat = 10  // 蓝标与文字间距
    var professionSpacing: CGFloat = 7       // 与上方元素的间距

    // ==================== 统计数据区域 ====================
    var statsTopPadding: CGFloat = 16        // 统计区域顶部间距
    var statsHorizontalPadding: CGFloat = 40 // 统计区域左右边距
    var statsLabelFontSize: CGFloat = 16     // 标签字体大小
    var statsValueFontSize: CGFloat = 16     // 数值字体大小
    var statsItemWidth: CGFloat = 132        // 每项宽度
    var statsItemSpacing: CGFloat = -16      // 项目之间间距
    var statsDividerHeight: CGFloat = 24     // 分隔线高度
    var statsDividerWidth: CGFloat = 1       // 分隔线宽度

    // ==================== 颜色 ====================
    var textColor: Color = .white
    var secondaryTextColor: Color = Color(red: 0.97, green: 0.97, blue: 0.97)

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

    // 计算显示的用户名（未填写时显示默认值）
    private var displayUsername: String {
        if let name = username, !name.isEmpty {
            return name
        }
        return "User"  // iOS 默认状态
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

                // 位置信息（未填写时不显示）
                if let location = location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: layout.locationFontSize))
                        .lineSpacing(19)
                        .foregroundColor(layout.textColor)
                }
            }

            // MARK: - 职业/身份信息（带蓝标）- 未填写时不显示
            if let profession = profession, !profession.isEmpty {
                HStack(spacing: layout.professionIconSpacing) {
                    // 蓝标认证图标
                    Image("Blue-v")
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.blueVIconSize, height: layout.blueVIconSize)

                    Text(profession)
                        .font(.system(size: layout.professionFontSize, weight: .light))
                        .lineSpacing(19)
                        .foregroundColor(layout.secondaryTextColor)
                }
            }

            // MARK: - 统计数据（Following / Followers / Likes）
            HStack(spacing: layout.statsItemSpacing) {
                // Following
                statsItem(label: "Following", value: "\(followingCount)")
                    .frame(width: layout.statsItemWidth)

                // 分隔线
                Rectangle()
                    .fill(layout.textColor)
                    .frame(width: layout.statsDividerWidth, height: layout.statsDividerHeight)

                // Followers
                statsItem(label: "Followers", value: "\(followersCount)")
                    .frame(width: layout.statsItemWidth)

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

// MARK: - Preview: 有完整信息的状态
#Preview("有信息") {
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

// MARK: - Preview: 未填写信息的默认状态
#Preview("未填写信息") {
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
