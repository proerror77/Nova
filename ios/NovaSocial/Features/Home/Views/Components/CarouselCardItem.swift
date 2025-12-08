import SwiftUI

// MARK: - Carousel Card Item

struct CarouselCardItem: View {
    let rankNumber: String
    let name: String
    let company: String
    let votes: String
    let imageAssetName: String

    var body: some View {
        VStack(spacing: 18) {
            // Image section (top)
            Image(imageAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 235, height: 250)
                .clipped()
                .cornerRadius(5)

            // Bottom section: Rank, Name/Company, and Votes
            HStack {
                HStack(spacing: 10) {
                    // Rank badge
                    Text(rankNumber)
                        .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                        .foregroundColor(.white)
                        .frame(width: 35, height: 35)
                        .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .cornerRadius(6)

                    // Name and company
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.bold))
                            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(company)
                            .font(Font.custom("Helvetica Neue", size: 14).weight(.medium))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                // Votes section
                VStack(spacing: 2) {
                    Image("card-heart-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                    Text(votes)
                        .font(Font.custom("Inter", size: 9))
                        .lineSpacing(13)
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 18)
        .frame(width: 274)
        .background(.white)
        .cornerRadius(5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rankNumber): \(name) from \(company), \(votes) votes")
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 0) {
        // MARK: - 标题部分
        HStack {
            Text("Hottest Banker in H.K.")
                .font(Font.custom("Helvetica Neue", size: 20).weight(.bold))
                .foregroundColor(.black)
                .padding(.leading, 20) // ← 调整标题左边距

            Spacer()

            Button(action: {}) {
                Text("See all")
                    .font(Font.custom("Helvetica Neue", size: 10).weight(.medium))
                    .foregroundColor(.white)
                    .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                    .cornerRadius(5)
            }
            .padding(.trailing, 0) // ← 调整按钮右边距
        }
        .padding(.horizontal, 16)
        .padding(.top, 0) // ← 调整标题区域与上方的间距
        .padding(.bottom, 5) // ← 调整标题区域与下方卡片的间距

        // MARK: - 轮播卡片容器
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                CarouselCardItem(
                    rankNumber: "1",
                    name: "Lucy Liu",
                    company: "Morgan Stanley",
                    votes: "2293",
                    imageAssetName: "PollCard-1"
                )

                CarouselCardItem(
                    rankNumber: "2",
                    name: "Jane Smith",
                    company: "Goldman Sachs",
                    votes: "1856",
                    imageAssetName: "PollCard-2"
                )

                CarouselCardItem(
                    rankNumber: "3",
                    name: "Emily Chen",
                    company: "JP Morgan",
                    votes: "1542",
                    imageAssetName: "PollCard-3"
                )
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 360)

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignTokens.backgroundColor)
}
