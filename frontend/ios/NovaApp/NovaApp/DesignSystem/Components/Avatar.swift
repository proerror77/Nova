import SwiftUI

/// User avatar with fallback to initials
struct Avatar: View {
    let imageURL: URL?
    let initials: String
    var size: CGFloat = Theme.AvatarSize.md
    var showBorder: Bool = false

    var body: some View {
        Group {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            showBorder ?
                Circle().stroke(Theme.Colors.border, lineWidth: 2) : nil
        )
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.primary.opacity(0.2))
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(Theme.Colors.primary)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        Avatar(imageURL: nil, initials: "JD", size: Theme.AvatarSize.sm)
        Avatar(imageURL: nil, initials: "AB", size: Theme.AvatarSize.md, showBorder: true)
        Avatar(imageURL: nil, initials: "XY", size: Theme.AvatarSize.lg)
    }
    .padding()
}
