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
        VStack(spacing: 18) {
            // Top section: Rank, Name/Company, and Votes
            HStack(spacing: 82) {
                HStack(spacing: 10) {
                    // Rank badge
                    VStack(spacing: 10) {
                        Text(rankNumber)
                            .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                            .foregroundColor(.white)
                    }
                    .padding(EdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11))
                    .frame(width: 35, height: 35)
                    .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                    .cornerRadius(6)

                    // Name and company
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.bold))
                            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                        Text(company)
                            .font(Font.custom("Helvetica Neue", size: 14).weight(.medium))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
                    }
                    .frame(width: 118)
                }

                // Votes section
                VStack(spacing: 0) {
                    ZStack {
                        // Icon placeholder (can be replaced with actual icon)
                    }
                    .frame(width: 24, height: 24)
                    Text(votes)
                        .font(Font.custom("Inter", size: 9))
                        .lineSpacing(13)
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
            .frame(width: 235)

            // Image section
            Image(imageAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 235, height: 250)
                .clipped()
                .cornerRadius(5)
        }
        .frame(width: 274, height: 340)
        .background(.white)
        .cornerRadius(5)
    }
}
