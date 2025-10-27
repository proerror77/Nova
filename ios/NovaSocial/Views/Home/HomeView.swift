import SwiftUI

/// Figma 设计的主页 - 包含推荐卡片和投票卡片
struct HomeView: View {
    @State private var recommendations: [RecommendationItem] = [
        RecommendationItem(
            title: "kyleegigstead",
            subtitle: "Cyborg dreams",
            imageURL: nil,
            commentCount: 93
        ),
    ]

    @State private var pollCandidates: [PollCandidate] = [
        PollCandidate(name: "Lucy Liu", organization: "Morgan Stanley", votes: 2293, imageURL: nil),
        PollCandidate(name: "Jane Smith", organization: "Goldman Sachs", votes: 1856, imageURL: nil),
        PollCandidate(name: "Emily Chen", organization: "JPMorgan", votes: 1624, imageURL: nil),
        PollCandidate(name: "Sarah Johnson", organization: "Bank of America", votes: 1432, imageURL: nil),
        PollCandidate(name: "Lisa Wong", organization: "HSBC", votes: 1289, imageURL: nil),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // 推荐卡片部分
                    VStack(spacing: DesignSystem.Spacing.md) {
                        ForEach(recommendations.indices, id: \.self) { index in
                            RecommendationCard(
                                title: recommendations[index].title,
                                subtitle: recommendations[index].subtitle,
                                imageURL: recommendations[index].imageURL,
                                commentCount: recommendations[index].commentCount,
                                onTap: {
                                    // Handle tap
                                }
                            )
                        }
                    }

                    // 投票卡片部分
                    PollCard(
                        title: "Hottest Banker in H.K.",
                        subtitle: "Corporate Poll",
                        candidates: pollCandidates,
                        onVote: { index in
                            // Handle vote
                            print("Voted for: \(pollCandidates[index].name)")
                        }
                    )

                    Spacer()
                        .frame(height: DesignSystem.Spacing.lg)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // Search action
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DesignSystem.Colors.textDark)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("ICERED")
                        .font(DesignSystem.Typography.subtitle)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // Notification action
                    } label: {
                        Image(systemName: "bell.fill")
                            .foregroundColor(DesignSystem.Colors.textDark)
                    }
                }
            }
        }
    }
}

struct RecommendationItem {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let commentCount: Int
}

#Preview {
    HomeView()
}
