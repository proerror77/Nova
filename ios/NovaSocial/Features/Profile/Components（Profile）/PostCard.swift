import SwiftUI

struct PostCard: View {
    // MARK: - Properties
    var imageUrl: String?
    var imageName: String = "PostCardImage"
    var title: String = "kyleegigstead Cyborg dreams..."
    var authorName: String = "Simone Carter"
    var authorAvatarUrl: String?
    var likeCount: Int = 2234
    var onTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // 图片区域 (272 - 55 = 217) - 使用 CachedAsyncImage 提供缓存和更好的性能
            if let imageUrl = imageUrl, let url = URL(string: imageUrl) {
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: 360, height: 434),  // 2x for Retina
                    priority: .normal
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView())
                }
                .frame(width: 180.w, height: 217.h)
                .clipped()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6.s, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 6.s))
            } else {
                // 使用本地图片作为后备
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180.w, height: 217.h)
                    .clipped()
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6.s, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 6.s))
            }

            // 底部内容区域 (55px)
            VStack(alignment: .leading, spacing: 6.s) {
                // 标题
                Text(title)
                    .font(Font.custom("SF Pro Display", size: 10.f))
                    .foregroundColor(.black)
                    .lineLimit(1)

                // 作者信息和点赞数
                HStack {
                    // 作者信息
                    HStack(spacing: 5.s) {
                        // 头像 - 使用 AvatarView 组件，无头像时显示首字母
                        AvatarView(
                            image: nil,
                            url: authorAvatarUrl,
                            size: 17.s,
                            name: authorName
                        )

                        Text(authorName)
                            .font(Font.custom("SF Pro Display", size: 10.f))
                            .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                            .lineLimit(1)
                    }

                    Spacer()

                    // 点赞数
                    HStack(spacing: 5.s) {
                        Image(systemName: "heart")
                            .font(.system(size: 12.f))
                            .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))

                        Text("\(likeCount)")
                            .font(Font.custom("SF Pro Display", size: 10.f))
                            .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                    }
                }
            }
            .padding(.horizontal, 10.w)
            .frame(width: 180.w, height: 55.h)
        }
        .frame(width: 180.w, height: 272.h)
        .background(.white)
        .cornerRadius(6.s)
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Preview
#Preview {
    PostCard()
        .padding()
        .background(Color.gray.opacity(0.2))
}
