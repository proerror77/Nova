import SwiftUI

// MARK: - Hottest Banker Section
/// 独立的轮播图区域组件，包含标题和卡片轮播
/// 可在 Feed 中按需插入

struct HottestBankerSection: View {
    var onSeeAllTapped: () -> Void = {}
    var pollId: String? = nil

    @State private var candidates: [PollCandidate] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let socialService = SocialService()

    // Default placeholder images
    private let placeholderImages = ["PollCard-1", "PollCard-2", "PollCard-3", "PollCard-4", "PollCard-5"]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 标题部分
            HStack {
                Text(LocalizedStringKey("Hottest Banker in H.K."))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)

                Spacer()

                Button(action: onSeeAllTapped) {
                    Text(LocalizedStringKey("View more"))
                        .font(.system(size: 10, weight: .medium))
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
                    if isLoading {
                        // Loading state with placeholder cards
                        ForEach(0..<3, id: \.self) { index in
                            CarouselCardItem(
                                rankNumber: "\(index + 1)",
                                name: "Loading...",
                                company: "",
                                votes: "--",
                                imageAssetName: placeholderImages[index % placeholderImages.count]
                            )
                            .redacted(reason: .placeholder)
                        }
                    } else if let error = errorMessage {
                        // Error state - show fallback mock data
                        Text(error)
                            .foregroundColor(.gray)
                            .frame(height: 300)
                    } else if candidates.isEmpty {
                        // Empty state
                        Text("No polls available")
                            .foregroundColor(.gray)
                            .frame(height: 300)
                    } else {
                        // Real data from API
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            CarouselCardItem(
                                rankNumber: "\(candidate.rank)",
                                name: candidate.name,
                                company: candidate.description ?? "",
                                votes: formatVotes(candidate.voteCount),
                                imageAssetName: placeholderImages[index % placeholderImages.count],
                                imageUrl: candidate.avatarUrl
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 360)
            .padding(.horizontal, -16)
        }
        .task {
            await loadPollData()
        }
    }

    // MARK: - Data Loading

    private func loadPollData() async {
        isLoading = true
        errorMessage = nil

        do {
            // First try to get trending polls to find the poll ID
            if let pollIdToUse = pollId {
                // If pollId is provided, load rankings for that poll
                candidates = try await socialService.getPollRankings(pollId: pollIdToUse, limit: 5)
            } else {
                // Otherwise, get trending polls and use the first one
                let trendingPolls = try await socialService.getTrendingPolls(limit: 1)
                if let firstPoll = trendingPolls.first {
                    candidates = try await socialService.getPollRankings(pollId: firstPoll.id, limit: 5)
                } else {
                    // No polls available, use empty state
                    candidates = []
                }
            }
        } catch {
            print("Error loading poll data: \(error)")
            errorMessage = nil // Don't show error to user, just show empty
            // Keep candidates empty to show placeholder
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func formatVotes(_ count: Int64) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
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
