import SwiftUI

/// 默认头像视图 - 在用户未设置头像时显示 iOS 风格的默认头像
struct DefaultAvatarView: View {
    let size: CGFloat
    var backgroundColor: Color = Color(red: 0.85, green: 0.85, blue: 0.85)
    var iconColor: Color = Color(red: 0.6, green: 0.6, blue: 0.6)

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: size, height: size)

            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundColor(iconColor)
                .offset(y: size * 0.05)
        }
        .clipShape(Circle())
    }
}

/// 通用头像视图 - 自动显示用户头像或默认头像
struct AvatarView: View {
    let image: UIImage?
    let url: String?
    let size: CGFloat
    var backgroundColor: Color = Color(red: 0.85, green: 0.85, blue: 0.85)

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let urlString = url, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        DefaultAvatarView(size: size, backgroundColor: backgroundColor)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        DefaultAvatarView(size: size, backgroundColor: backgroundColor)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                DefaultAvatarView(size: size, backgroundColor: backgroundColor)
            }
        }
    }
}

// MARK: - Previews

#Preview("Avatar - Default") {
    VStack(spacing: 20) {
        DefaultAvatarView(size: 136)
        DefaultAvatarView(size: 100)
        DefaultAvatarView(size: 60)
        DefaultAvatarView(size: 40)
    }
    .padding()
    .background(Color.black.opacity(0.3))
}

#Preview("Avatar - Dark Mode") {
    VStack(spacing: 20) {
        DefaultAvatarView(size: 136)
        DefaultAvatarView(size: 100)
        DefaultAvatarView(size: 60)
        DefaultAvatarView(size: 40)
    }
    .padding()
    .background(Color.black.opacity(0.3))
    .preferredColorScheme(.dark)
}

#Preview("AvatarView - No Image") {
    AvatarView(image: nil, url: nil, size: 100)
}

#Preview("AvatarView - Dark Mode") {
    AvatarView(image: nil, url: nil, size: 100)
        .preferredColorScheme(.dark)
}
