import SwiftUI
import Kingfisher

/// Figma 设计的推荐卡片 - "kyleegigstead Cyborg dreams"
struct RecommendationCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let commentCount: Int
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 图片部分
            ZStack {
                if let imageURL {
                    KFImage(imageURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(DesignSystem.Colors.background)
                }
            }
            .frame(height: 200)
            .cornerRadius(DesignSystem.CornerRadius.large, corners: [.topLeft, .topRight])

            // 内容部分
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(DesignSystem.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.textDark)

                        Text(subtitle)
                            .font(DesignSystem.Typography.label)
                            .foregroundColor(DesignSystem.Colors.textMedium)
                    }

                    Spacer()

                    // 评论数
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right.fill")
                            .font(.system(size: 12))
                        Text("\(commentCount)")
                            .font(DesignSystem.Typography.label)
                    }
                    .foregroundColor(DesignSystem.Colors.textMedium)
                }

                Divider()
                    .foregroundColor(DesignSystem.Colors.divider)
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .applyCardStyle()
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Corner Radius Helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    VStack(spacing: 16) {
        RecommendationCard(
            title: "kyleegigstead",
            subtitle: "Cyborg dreams",
            imageURL: nil,
            commentCount: 93,
            onTap: {}
        )
        Spacer()
    }
    .padding(DesignSystem.Spacing.lg)
    .background(DesignSystem.Colors.background)
}
