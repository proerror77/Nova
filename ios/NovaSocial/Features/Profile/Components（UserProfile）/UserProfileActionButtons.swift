import SwiftUI

// MARK: - UserProfile Action Buttons Layout Configuration
struct UserProfileActionButtonsLayout {
    // ==================== 按钮尺寸 ====================
    var buttonWidth: CGFloat = 105
    var buttonHeight: CGFloat = 34
    var buttonCornerRadius: CGFloat = 17
    var buttonSpacing: CGFloat = 10
    var buttonFontSize: CGFloat = 12

    // ==================== 间距 ====================
    var topPadding: CGFloat = 16
    var bottomPadding: CGFloat = 20

    // ==================== 颜色 ====================
    var primaryButtonColor: Color = Color(red: 0.87, green: 0.11, blue: 0.26)
    var textColor: Color = .white
    var outlineColor: Color = Color.white.opacity(0.5)
    var outlineWidth: CGFloat = 1

    static let `default` = UserProfileActionButtonsLayout()
}

// MARK: - UserProfile Action Buttons Component
struct UserProfileActionButtons: View {
    // State
    @Binding var isFollowing: Bool

    // Layout
    var layout: UserProfileActionButtonsLayout = .default

    // Actions
    var onFollowTapped: () -> Void = {}
    var onAddFriendsTapped: () -> Void = {}
    var onMessageTapped: () -> Void = {}

    var body: some View {
        HStack(spacing: layout.buttonSpacing) {
            // MARK: - Follow/Following 按钮（实心）
            Button(action: {
                isFollowing.toggle()
                onFollowTapped()
            }) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: layout.buttonFontSize))
                    .foregroundColor(layout.textColor)
                    .frame(width: layout.buttonWidth, height: layout.buttonHeight)
                    .background(layout.primaryButtonColor)
                    .cornerRadius(layout.buttonCornerRadius)
            }

            // MARK: - Add friends 按钮（描边）
            Button(action: onAddFriendsTapped) {
                Text("Add friends")
                    .font(.system(size: layout.buttonFontSize))
                    .foregroundColor(layout.textColor)
                    .frame(width: layout.buttonWidth, height: layout.buttonHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.buttonCornerRadius)
                            .stroke(layout.outlineColor, lineWidth: layout.outlineWidth)
                    )
            }

            // MARK: - Message 按钮（描边）
            Button(action: onMessageTapped) {
                Text("Message")
                    .font(.system(size: layout.buttonFontSize))
                    .foregroundColor(layout.textColor)
                    .frame(width: layout.buttonWidth, height: layout.buttonHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.buttonCornerRadius)
                            .stroke(layout.outlineColor, lineWidth: layout.outlineWidth)
                    )
            }
        }
        .frame(maxWidth: .infinity)  // 确保居中
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
    }
}

// MARK: - Previews
#Preview("UserProfileActionButtons - Following") {
    ZStack {
        Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
            .ignoresSafeArea()

        UserProfileActionButtons(
            isFollowing: .constant(true)
        )
    }
}

#Preview("UserProfileActionButtons - Not Following") {
    ZStack {
        Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
            .ignoresSafeArea()

        UserProfileActionButtons(
            isFollowing: .constant(false)
        )
    }
}
