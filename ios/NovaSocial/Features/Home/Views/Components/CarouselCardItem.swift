import SwiftUI

// MARK: - Carousel Card Item

struct CarouselCardItem: View {
    let rankNumber: String
    let name: String
    let company: String
    let votes: String
    let imageAssetName: String
    var imageUrl: String? = nil  // Optional URL for remote images

    var body: some View {
        VStack(spacing: 18) {
            // Image section (top) - using CachedAsyncImage for disk caching
            if let urlString = imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: 235 * 2, height: 250 * 2)  // 2x for Retina displays
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 235, height: 250)
                        .clipped()
                        .cornerRadius(5)
                } placeholder: {
                    ProgressView()
                        .frame(width: 235, height: 250)
                }
            } else {
                Image(imageAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 235, height: 250)
                    .clipped()
                    .cornerRadius(5)
            }

            // Bottom section: Rank, Name/Company, and Votes
            HStack {
                HStack(spacing: 10) {
                    // Rank badge
                    Text(rankNumber)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 35, height: 35)
                        .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .cornerRadius(6)

                    // Name and company
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(company)
                            .font(.system(size: 14, weight: .medium))
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
                        .font(.system(size: 9))
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

// MARK: - Previews

#Preview("CarouselCard - Default") {
    VStack(spacing: 0) {
        // MARK: - 标题部分
        HStack {
            Text("Hottest Banker in H.K.")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)

            Spacer()

            Button(action: {}) {
                Text("View more")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 5)

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

#Preview("CarouselCard - Dark Mode") {
    VStack(spacing: 0) {
        HStack {
            Text("Hottest Banker in H.K.")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)

            Spacer()

            Button(action: {}) {
                Text("View more")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 5)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                CarouselCardItem(
                    rankNumber: "1",
                    name: "Lucy Liu",
                    company: "Morgan Stanley",
                    votes: "2293",
                    imageAssetName: "PollCard-1"
                )
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 360)

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignTokens.backgroundColor)
    .preferredColorScheme(.dark)
}
