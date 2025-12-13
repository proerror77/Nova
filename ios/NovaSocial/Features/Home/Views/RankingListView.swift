import SwiftUI

// MARK: - Ranking List View

struct RankingListView: View {
    @Binding var currentPage: AppPage
    var pollId: String? = nil
    var pollTitle: String = "Hottest Banker in H.K."

    @State private var candidates: [PollCandidate] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var hasVoted = false
    @State private var votedCandidateId: String?
    @State private var isVoting = false

    private let socialService = SocialService()

    // Filtered candidates based on search
    private var filteredCandidates: [PollCandidate] {
        if searchText.isEmpty {
            return candidates
        }
        return candidates.filter { candidate in
            candidate.name.localizedCaseInsensitiveContains(searchText) ||
            (candidate.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

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
                        Text(pollTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                        Text("Corporate Poll")
                            .font(.system(size: 12, weight: .medium))
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
                            TextField("Search", text: $searchText)
                                .font(.system(size: 15))
                                .foregroundColor(.black)
                        }
                        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .frame(height: 32)
                        .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                        .cornerRadius(32)
                        .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                        // Ranking List Items
                        VStack(spacing: 16) {
                            if isLoading {
                                // Loading state
                                ForEach(0..<5, id: \.self) { index in
                                    RankingListItem(
                                        rank: "\(index + 1)",
                                        name: "Loading...",
                                        company: "",
                                        votes: "--",
                                        percentage: "--%",
                                        rankColor: Color(red: 0.68, green: 0.68, blue: 0.68),
                                        hasFullIndicators: false,
                                        isVoted: false,
                                        onVote: {}
                                    )
                                    .redacted(reason: .placeholder)
                                }
                            } else if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.gray)
                                    .padding()
                            } else if filteredCandidates.isEmpty {
                                Text(searchText.isEmpty ? "No candidates available" : "No results found")
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(filteredCandidates) { candidate in
                                    RankingListItem(
                                        rank: "\(candidate.rank)",
                                        name: candidate.name,
                                        company: candidate.description ?? "",
                                        votes: "\(candidate.voteCount)",
                                        percentage: String(format: "%.0f%%", candidate.votePercentage),
                                        rankColor: rankColor(for: candidate.rank),
                                        hasFullIndicators: candidate.rank <= 3,
                                        hasFirstIndicator: candidate.rank == 1,
                                        avatarUrl: candidate.avatarUrl,
                                        isVoted: votedCandidateId == candidate.id,
                                        onVote: {
                                            Task {
                                                await voteForCandidate(candidate)
                                            }
                                        }
                                    )
                                    .disabled(isVoting)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        // Vote again notice
                        if hasVoted {
                            ZStack {
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(height: 31)
                                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))
                                    .cornerRadius(99)
                                Text("You may vote again in 24h")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: 280)
                            .padding(.top, 24)
                            .padding(.bottom, 32)
                        } else {
                            Spacer()
                                .frame(height: 32)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .navigationBarBackButtonHidden(true)
        .task {
            await loadData()
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Determine which poll to load
            let targetPollId: String
            if let id = pollId {
                targetPollId = id
            } else {
                // Get trending polls and use the first one
                let trendingPolls = try await socialService.getTrendingPolls(limit: 1)
                guard let firstPoll = trendingPolls.first else {
                    errorMessage = "No polls available"
                    isLoading = false
                    return
                }
                targetPollId = firstPoll.id
            }

            // Load rankings for the poll
            candidates = try await socialService.getPollRankings(pollId: targetPollId, limit: 20)

            // Check if user has already voted
            hasVoted = try await socialService.checkPollVoted(pollId: targetPollId)

        } catch {
            print("Error loading ranking data: \(error)")
            errorMessage = "Failed to load rankings"
        }

        isLoading = false
    }

    // MARK: - Voting

    private func voteForCandidate(_ candidate: PollCandidate) async {
        guard !isVoting else { return }

        isVoting = true

        do {
            // Determine which poll to vote on
            let targetPollId: String
            if let id = pollId {
                targetPollId = id
            } else {
                let trendingPolls = try await socialService.getTrendingPolls(limit: 1)
                guard let firstPoll = trendingPolls.first else {
                    isVoting = false
                    return
                }
                targetPollId = firstPoll.id
            }

            // Submit vote
            try await socialService.voteOnPoll(pollId: targetPollId, candidateId: candidate.id)

            // Update local state
            votedCandidateId = candidate.id
            hasVoted = true

            // Reload data to get updated vote counts
            await loadData()

        } catch {
            print("Error voting: \(error)")
            // Could show an alert here
        }

        isVoting = false
    }

    // MARK: - Helpers

    private func rankColor(for rank: Int) -> Color {
        if rank <= 3 {
            return Color(red: 0.82, green: 0.13, blue: 0.25) // Red for top 3
        }
        return Color(red: 0.68, green: 0.68, blue: 0.68) // Gray for others
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
    var avatarUrl: String? = nil
    var isVoted: Bool = false
    var onVote: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            // Rank number - smaller font
            Text(rank)
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(rankColor)
                .frame(width: 45, alignment: .center)

            // Avatar
            if let urlString = avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                            .frame(width: 48, height: 48)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    case .failure:
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                            .frame(width: 48, height: 48)
                    @unknown default:
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                            .frame(width: 48, height: 48)
                    }
                }
            } else {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 48, height: 48)
            }

            // Name, company, and progress
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))

                Text(company)
                    .font(.system(size: 10, weight: .medium))
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
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(red: 0.68, green: 0.68, blue: 0.68))
                        .padding(.leading, 7)
                }
            }

            Spacer()

            // Heart icon and percentage - tappable for voting
            Button(action: onVote) {
                VStack(spacing: 4) {
                    Image(systemName: isVoted ? "heart.fill" : "heart")
                        .font(.system(size: 24))
                        .foregroundColor(isVoted ? Color(red: 0.82, green: 0.13, blue: 0.25) : Color(red: 0.2, green: 0.2, blue: 0.2))
                    Text(percentage)
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
            .buttonStyle(PlainButtonStyle())
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
