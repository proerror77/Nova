import SwiftUI

// MARK: - Comment Card Item

struct CommentCardItem: View {
    var hasExtraField: Bool = false
    let imageAssetName: String
    @Binding var showReportView: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - User Info Header
            HStack(spacing: DesignTokens.spacing10) {
                // Avatar
                Circle()
                    .fill(DesignTokens.avatarPlaceholder)
                    .frame(width: DesignTokens.avatarMedium, height: DesignTokens.avatarMedium)

                // User info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simone Carter")
                        .font(.system(size: DesignTokens.fontMedium, weight: .semibold))
                        .foregroundColor(.black)

                    Text("1d")
                        .font(.system(size: DesignTokens.fontCaption))
                        .foregroundColor(DesignTokens.textMuted)
                }

                Spacer()

                // Menu button - opens ReportModal
                Button(action: {
                    showReportView = true
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.black)
                        .font(.system(size: DesignTokens.fontMedium))
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, DesignTokens.spacing12)
            .padding(.vertical, DesignTokens.spacing10)

            // MARK: - Main Image
            Image(imageAssetName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, minHeight: 200)
                .clipped()
                .cornerRadius(DesignTokens.cardCornerRadius)
                .padding(.horizontal, DesignTokens.spacing12)
                .padding(.vertical, DesignTokens.spacing8)

            // MARK: - Page Indicators
            HStack(spacing: DesignTokens.spacing6) {
                Circle()
                    .fill(DesignTokens.indicatorActive)
                    .frame(width: DesignTokens.spacing6, height: DesignTokens.spacing6)

                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(DesignTokens.indicatorInactive)
                        .frame(width: DesignTokens.spacing6, height: DesignTokens.spacing6)
                }
            }
            .padding(.horizontal, 160)
            .padding(.vertical, DesignTokens.spacing6)

            // MARK: - Comment Text
            HStack(spacing: DesignTokens.spacing4) {
                Text("kyleegigstead Cyborg dreams...")
                    .font(.system(size: DesignTokens.fontBody))
                    .foregroundColor(.black)

                Text("up")
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundColor(DesignTokens.textMuted)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.spacing12)
            .padding(.vertical, DesignTokens.spacing8)

            // MARK: - Interaction Buttons
            HStack(spacing: DesignTokens.spacing16) {
                InteractionButton(icon: "arrowtriangle.up.fill", label: "0")
                InteractionButton(icon: "arrowtriangle.down.fill", label: "0")
                InteractionButton(icon: "bubble.right", label: "0")
                InteractionButton(icon: "square.and.arrow.up", label: "Share")

                Spacer()

                Image(systemName: "bookmark")
                    .font(.system(size: DesignTokens.fontSmall))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, DesignTokens.spacing12)
            .padding(.vertical, DesignTokens.spacing8)
        }
        .background(DesignTokens.cardBackground)
        .cornerRadius(DesignTokens.cardCornerRadius)
    }
}

// MARK: - Interaction Button Helper

private struct InteractionButton: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: DesignTokens.spacing6) {
            Image(systemName: icon)
                .font(.system(size: DesignTokens.spacing10))
                .foregroundColor(.black)
            Text(label)
                .font(.system(size: DesignTokens.fontSmall, weight: .bold))
                .foregroundColor(.black)
        }
    }
}
