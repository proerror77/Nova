import SwiftUI

// MARK: - Empty Feed State View

struct EmptyFeedView: View {
    var onRefresh: (() async -> Void)?
    var onCreatePost: (() -> Void)?

    var body: some View {
        VStack(spacing: DesignTokens.spacing16) {
            // Icon
            Image(systemName: "photo.stack")
                .font(.system(size: 50.f))
                .foregroundColor(DesignTokens.accentColor.opacity(0.6))

            // Title
            Text("No posts yet")
                .font(Font.custom("SFProDisplay-Semibold", size: DesignTokens.fontTitle))
                .foregroundColor(DesignTokens.textPrimary)

            // Subtitle
            Text("Be the first to share something!")
                .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontMedium))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)

            // Action Buttons
            HStack(spacing: DesignTokens.spacing12) {
                // Refresh Button
                if let onRefresh = onRefresh {
                    Button(action: {
                        Task { await onRefresh() }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14.f))
                            Text("Refresh")
                                .font(Font.custom("SFProDisplay-Medium", size: DesignTokens.fontMedium))
                        }
                        .foregroundColor(DesignTokens.accentColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, DesignTokens.spacing10)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.buttonCornerRadius)
                                .stroke(DesignTokens.accentColor, lineWidth: 1.5)
                        )
                    }
                }

                // Create Post Button
                if let onCreatePost = onCreatePost {
                    Button(action: onCreatePost) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 14.f))
                            Text("Create Post")
                                .font(Font.custom("SFProDisplay-Medium", size: DesignTokens.fontMedium))
                        }
                        .foregroundColor(DesignTokens.textOnAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, DesignTokens.spacing10)
                        .background(DesignTokens.accentColor)
                        .cornerRadius(DesignTokens.buttonCornerRadius)
                    }
                }
            }
            .padding(.top, DesignTokens.spacing8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, DesignTokens.spacing20)
    }
}

// MARK: - Preview

#Preview("Empty Feed View") {
    EmptyFeedView(
        onRefresh: {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        },
        onCreatePost: {
            print("Create post tapped")
        }
    )
}

#Preview("Empty Feed - No Actions") {
    EmptyFeedView()
}
