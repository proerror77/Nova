import SwiftUI

/// 活动/广告展示区域组件 - Feed 顶部推广内容
struct PromoBannerView: View {
    var onTap: (() -> Void)?

    private let cardWidth: CGFloat = 343
    private let cardHeight: CGFloat = 65
    private let cardSpacing: CGFloat = 32

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: cardSpacing) {
                ForEach(0..<2, id: \.self) { _ in
                    bannerCard
                }
            }
            .padding(.horizontal, (UIScreen.main.bounds.width - cardWidth) / 2)
        }
        .frame(height: cardHeight + 20)
    }

    private var bannerCard: some View {
        Button(action: { onTap?() }) {
            RoundedRectangle(cornerRadius: 5)
                .fill(DesignTokens.tileBackground)
                .frame(width: cardWidth, height: cardHeight)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("PromoBanner - Default") {
    PromoBannerView()
        .background(DesignTokens.backgroundColor)
}

#Preview("PromoBanner - Dark Mode") {
    PromoBannerView()
        .background(DesignTokens.backgroundColor)
        .preferredColorScheme(.dark)
}
