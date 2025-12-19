import SwiftUI

// MARK: - Hottest Banker Section
/// 独立的轮播图区域组件，包含标题和卡片轮播
/// 可在 Feed 中按需插入

struct HottestBankerSection: View {
    var onSeeAllTapped: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 标题部分
            HStack {
                Text(LocalizedStringKey("Hottest Banker in H.K."))
                    .font(Typography.bold20)
                    .foregroundColor(.black)

                Spacer()

                Button(action: onSeeAllTapped) {
                    Text(LocalizedStringKey("View more"))
                        .font(Typography.regular10)
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 5)

            // MARK: - 轮播卡片容器 (水平滚动)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // 卡片 1
                    CarouselCardItem(
                        rankNumber: "1",
                        name: "Lucy Liu",
                        company: "Morgan Stanley",
                        votes: "2293",
                        imageAssetName: "PollCard-1"
                    )

                    // 卡片 2
                    CarouselCardItem(
                        rankNumber: "2",
                        name: "Lucy Liu",
                        company: "Morgan Stanley",
                        votes: "2293",
                        imageAssetName: "PollCard-2"
                    )

                    // 卡片 3
                    CarouselCardItem(
                        rankNumber: "3",
                        name: "Lucy Liu",
                        company: "Morgan Stanley",
                        votes: "2293",
                        imageAssetName: "PollCard-3"
                    )

                    // 卡片 4
                    CarouselCardItem(
                        rankNumber: "4",
                        name: "Lucy Liu",
                        company: "Morgan Stanley",
                        votes: "2293",
                        imageAssetName: "PollCard-4"
                    )

                    // 卡片 5
                    CarouselCardItem(
                        rankNumber: "5",
                        name: "Lucy Liu",
                        company: "Morgan Stanley",
                        votes: "2293",
                        imageAssetName: "PollCard-5"
                    )
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 360)
            .padding(.horizontal, -16)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        HottestBankerSection()
        Spacer()
    }
    .padding(.horizontal, 16)
    .background(DesignTokens.backgroundColor)
}
