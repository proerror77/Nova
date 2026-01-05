import SwiftUI

// MARK: - Feed Error State View

struct FeedErrorView: View {
    let errorMessage: String
    var onRetry: (() async -> Void)?
    var onLogin: (() -> Void)?

    // Detect if error requires login
    private var requiresLogin: Bool {
        errorMessage.lowercased().contains("session expired") ||
        errorMessage.lowercased().contains("login") ||
        errorMessage.lowercased().contains("unauthorized")
    }

    var body: some View {
        VStack(spacing: DesignTokens.spacing16) {
            // Error Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50.f))
                .foregroundColor(.orange)

            // Title
            Text("Oops!")
                .font(Font.custom("SFProDisplay-Semibold", size: DesignTokens.fontTitle))
                .foregroundColor(DesignTokens.textPrimary)

            // Error Message
            Text(errorMessage)
                .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontMedium))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, DesignTokens.spacing20)

            // Action Button
            if requiresLogin {
                // Show login button for auth errors
                if let onLogin = onLogin {
                    Button(action: onLogin) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 16.f))
                            Text("Login")
                                .font(Font.custom("SFProDisplay-Medium", size: DesignTokens.fontMedium))
                        }
                        .foregroundColor(DesignTokens.textOnAccent)
                        .padding(.horizontal, 32)
                        .padding(.vertical, DesignTokens.spacing12)
                        .background(DesignTokens.accentColor)
                        .cornerRadius(DesignTokens.buttonCornerRadius)
                    }
                    .padding(.top, DesignTokens.spacing8)
                }
            } else {
                // Show retry button for other errors
                if let onRetry = onRetry {
                    Button(action: {
                        Task { await onRetry() }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16.f))
                            Text("Try Again")
                                .font(Font.custom("SFProDisplay-Medium", size: DesignTokens.fontMedium))
                        }
                        .foregroundColor(DesignTokens.textOnAccent)
                        .padding(.horizontal, 32)
                        .padding(.vertical, DesignTokens.spacing12)
                        .background(DesignTokens.accentColor)
                        .cornerRadius(DesignTokens.buttonCornerRadius)
                    }
                    .padding(.top, DesignTokens.spacing8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, DesignTokens.spacing20)
    }
}

// MARK: - Preview

#Preview("Network Error") {
    FeedErrorView(
        errorMessage: "Unable to connect to the server. Please check your internet connection.",
        onRetry: {
            print("Retry tapped")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    )
}

#Preview("Session Expired") {
    FeedErrorView(
        errorMessage: "Session expired. Please login again.",
        onLogin: {
            print("Login tapped")
        }
    )
}

#Preview("Server Error") {
    FeedErrorView(
        errorMessage: "Failed to load feed. Please try again later.",
        onRetry: {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    )
}

#Preview("No Actions") {
    FeedErrorView(
        errorMessage: "Something went wrong"
    )
}
