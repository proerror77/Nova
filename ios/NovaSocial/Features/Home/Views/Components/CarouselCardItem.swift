import SwiftUI

// MARK: - Carousel Card Item

struct CarouselCardItem: View {
    let rankNumber: String
    let name: String
    let company: String
    let votes: String
    let isActive: Bool
    let imageAssetName: String

    var body: some View {
        VStack(spacing: DesignTokens.spacing16) {
            // Image area
            Image(imageAssetName)
                .resizable()
                .scaledToFill()
                .frame(height: 250)
                .clipped()
                .cornerRadius(15)

            // Rank and info
            HStack(spacing: DesignTokens.spacing12) {
                Text(rankNumber)
                    .font(.system(size: DesignTokens.fontLarge, weight: .bold))
                    .foregroundColor(DesignTokens.textOnAccent)
                    .frame(width: 35, height: 35)
                    .background(DesignTokens.accentColor)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: DesignTokens.spacing4) {
                    Text(name)
                        .font(.system(size: DesignTokens.fontLarge, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(company)
                        .font(.system(size: DesignTokens.fontSmall, weight: .medium))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Spacer()

                Text(votes)
                    .font(.system(size: DesignTokens.fontSmall, weight: .medium))
                    .foregroundColor(DesignTokens.textSecondary)
            }
        }
        .padding()
        .background(DesignTokens.cardBackground)
        .cornerRadius(DesignTokens.cardCornerRadius)
        .frame(width: 310)
    }
}
