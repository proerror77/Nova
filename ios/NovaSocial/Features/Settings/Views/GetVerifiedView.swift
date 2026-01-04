import SwiftUI

struct GetVerifiedView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            DesignTokens.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                topNavigationBar
                contentSection
            }
        }
    }

    // MARK: - Navigation Bar
    private var topNavigationBar: some View {
        HStack {
            Button(action: { currentPage = .profileSetting }) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .foregroundColor(DesignTokens.textPrimary)
            }
            .frame(width: 50, alignment: .leading)

            Spacer()

            Text("Get verified")
                .font(Font.custom("SFProDisplay-Medium", size: 18.f))
                .foregroundColor(DesignTokens.textPrimary)

            Spacer()

            Button(action: { /* TODO: Show help */ }) {
                Text("Help")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(DesignTokens.textPrimary)
            }
            .frame(width: 50, alignment: .trailing)
        }
        .frame(height: 60)
        .padding(.horizontal, 20)
        .background(DesignTokens.surface)
    }

    // MARK: - Content Section
    private var contentSection: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 80)

            // Avatar
            Circle()
                .fill(DesignTokens.avatarPlaceholder)
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(Font.custom("SFProDisplay-Regular", size: 40.f))
                        .foregroundColor(.white.opacity(0.8))
                )
                .padding(.bottom, 40)

            // Title
            Text("Profile verification required")
                .font(Font.custom("SFProDisplay-Bold", size: 20.f))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(.bottom, 16)

            // Description
            Text("Recent activity has caused us to lock your account. To continue swiping, please verify your profile photos.")
                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()

            // Action Button
            Button(action: { /* TODO: Handle verification */ }) {
                Text("Get started")
                    .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(DesignTokens.accentColor)
                    .cornerRadius(23)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Previews

#Preview("GetVerified - Default") {
    GetVerifiedView(currentPage: .constant(.getVerified))
}

#Preview("GetVerified - Dark Mode") {
    GetVerifiedView(currentPage: .constant(.getVerified))
        .preferredColorScheme(.dark)
}
