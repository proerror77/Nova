import SwiftUI

// MARK: - Bottom Tab Bar

struct BottomTabBar: View {
    @Binding var currentPage: AppPage
    @Binding var showPhotoOptions: Bool

    private var isHome: Bool { currentPage == .home }
    private var isMessage: Bool { currentPage == .message }
    private var isAccount: Bool { currentPage == .account }
    private var isAlice: Bool { currentPage == .alice }

    var body: some View {
        HStack(spacing: -20) {
            // Home
            VStack(spacing: 2) {
                Image(isHome ? "home-icon" : "home-icon-black")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 22)
                Text("Home")
                    .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                    .foregroundColor(isHome ? DesignTokens.accentColor : .black)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .home
            }

            // Message
            VStack(spacing: DesignTokens.spacing4) {
                Image(isMessage ? "Message-icon-red" : "Message-icon-black")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text("Message")
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundColor(isMessage ? DesignTokens.accentColor : .black)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .message
            }

            // New Post
            NewPostButtonComponent(showNewPost: $showPhotoOptions)

            // Alice
            VStack(spacing: -12) {
                Image(isAlice ? "alice-button-on" : "alice-button-off")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text("")
                    .font(.system(size: DesignTokens.fontCaption))
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .alice
            }

            // Account
            VStack(spacing: -12) {
                Image(isAccount ? "Account-button-on" : "Account-button-off")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text("")
                    .font(.system(size: DesignTokens.fontCaption))
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .account
            }
        }
        .frame(height: DesignTokens.bottomBarHeight)
        .padding(.bottom, 30) // ← 调整底部留白
        .background(
            DesignTokens.cardBackground
                .ignoresSafeArea(edges: .bottom)
        )
        .border(DesignTokens.borderColor, width: 0.5)
        .offset(y: 40) // ← 调整整体垂直位置：负值向上，正值向下
    }
}

// MARK: - New Post Button Component

struct NewPostButtonComponent: View {
    @State private var isPressed = false
    @Binding var showNewPost: Bool

    var body: some View {
        VStack(spacing: -10) {
            Image("Newpost-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .opacity(isPressed ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isPressed)
            Text("")
                .font(.system(size: DesignTokens.fontCaption))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showNewPost = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPressed = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        BottomTabBar(
            currentPage: .constant(.home),
            showPhotoOptions: .constant(false)
        )
    }
}
