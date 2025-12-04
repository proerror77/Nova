import SwiftUI

// MARK: - Ranking List View

struct RankingListView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top navigation bar
                HStack(spacing: 0) {
                    Button(action: {
                        currentPage = .home
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.black)
                    }

                    Spacer()

                    VStack(spacing: 5) {
                        Text("Hottest Banker in H.K.")
                            .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                        Text("Corporate Poll")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
                    }

                    Spacer()

                    Button(action: {
                        // Share action
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .padding(.horizontal, 16)
                .background(.white)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(red: 0.85, green: 0.85, blue: 0.85)),
                    alignment: .bottom
                )

                // Scrollable content
                ScrollView {
                    VStack(spacing: -2) {
                        // Search bar
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))
                            Text("Search")
                                .font(Font.custom("Helvetica Neue", size: 15))
                                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))
                            Spacer()
                        }
                        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .frame(height: 32)
                        .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                        .cornerRadius(32)
                        .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                        // Ranking List Items
                        VStack(spacing: 16) {
                            // Rank 1
                            RankingListItem(
                                rank: "1",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.82, green: 0.13, blue: 0.25),
                                hasFullIndicators: true
                            )

                            // Rank 2
                            RankingListItem(
                                rank: "2",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.82, green: 0.13, blue: 0.25),
                                hasFullIndicators: false,
                                hasFirstIndicator: false
                            )

                            // Rank 3
                            RankingListItem(
                                rank: "3",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.82, green: 0.13, blue: 0.25),
                                hasFullIndicators: true
                            )

                            // Rank 4
                            RankingListItem(
                                rank: "4",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.68, green: 0.68, blue: 0.68),
                                hasFullIndicators: false
                            )

                            // Rank 5
                            RankingListItem(
                                rank: "5",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.68, green: 0.68, blue: 0.68),
                                hasFullIndicators: true
                            )

                            // Rank 6
                            RankingListItem(
                                rank: "6",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.68, green: 0.68, blue: 0.68),
                                hasFullIndicators: true
                            )

                            // Rank 7
                            RankingListItem(
                                rank: "7",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.68, green: 0.68, blue: 0.68),
                                hasFullIndicators: true
                            )

                            // Rank 8
                            RankingListItem(
                                rank: "8",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.68, green: 0.68, blue: 0.68),
                                hasFullIndicators: true
                            )

                            // Rank 9
                            RankingListItem(
                                rank: "9",
                                name: "Lucy Liu",
                                company: "Morgan Stanley",
                                votes: "166",
                                percentage: "30%",
                                rankColor: Color(red: 0.68, green: 0.68, blue: 0.68),
                                hasFullIndicators: true
                            )
                        }
                        .padding(.horizontal, 16)

                        // Vote again notice
                        ZStack {
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(height: 31)
                                .background(Color(red: 0.74, green: 0.74, blue: 0.74))
                                .cornerRadius(99)
                            Text("Comfire you may vote again on 24h")
                                .font(Font.custom("Helvetica Neue", size: 13))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: 280)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Ranking List Item Component

struct RankingListItem: View {
    let rank: String
    let name: String
    let company: String
    let votes: String
    let percentage: String
    let rankColor: Color
    var hasFullIndicators: Bool = true
    var hasFirstIndicator: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // Rank number - smaller font
            Text(rank)
                .font(Font.custom("Helvetica Neue", size: 40).weight(.medium))
                .foregroundColor(rankColor)
                .frame(width: 45, alignment: .center)

            // Avatar - smaller size
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 48, height: 48)

            // Name, company, and progress
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                    .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))

                Text(company)
                    .font(Font.custom("Helvetica Neue", size: 10).weight(.medium))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))

                // Progress indicators - overlapping circles
                HStack(spacing: 0) {
                    HStack(spacing: -2.75) {
                        Circle()
                            .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                            .frame(width: 11, height: 11)

                        if hasFullIndicators {
                            Circle()
                                .fill(Color(red: 1, green: 0.78, blue: 0.78))
                                .frame(width: 11, height: 11)
                            Circle()
                                .fill(Color(red: 0.98, green: 0.45, blue: 0.09))
                                .frame(width: 11, height: 11)
                        }

                        if hasFirstIndicator {
                            Circle()
                                .strokeBorder(Color(red: 0.82, green: 0.13, blue: 0.25), lineWidth: 0.34)
                                .background(Circle().fill(Color.white))
                                .frame(width: 11, height: 11)
                        }
                    }

                    Text(votes)
                        .font(Font.custom("Helvetica Neue", size: 8).weight(.medium))
                        .foregroundColor(Color(red: 0.68, green: 0.68, blue: 0.68))
                        .padding(.leading, 7)
                }
            }

            Spacer()

            // Heart icon and percentage - smaller
            VStack(spacing: 4) {
                Image(systemName: "heart")
                    .font(.system(size: 24))
                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                Text(percentage)
                    .font(Font.custom("Inter", size: 9))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 0)
        .frame(height: 79)
        .background(Color.white)
        .cornerRadius(5)
    }
}

#Preview {
    RankingListView(currentPage: .constant(.home))
}
