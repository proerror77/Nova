import SwiftUI

public struct HomeView: View {
    public init() {}
    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var currentPollIndex = 0

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.97, green: 0.96, blue: 0.96)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Poll Section
                        PollSectionView(currentIndex: $currentPollIndex)
                            .padding(.top, 16)

                        // Feed Section
                        if isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if let error = error {
                            ErrorView(message: error)
                                .padding(.top, 40)
                        } else if posts.isEmpty {
                            EmptyFeedView()
                                .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(posts) { post in
                                    FeedPostCard(post: post)
                                }
                            }
                            .padding(.top, 24)
                        }

                        // Bottom padding for custom tab bar
                        Color.clear
                            .frame(height: 72)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {}) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.black)
                            .font(.system(size: 22))
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("ICERED")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                        .tracking(1.5) // Letter spacing for brand feel
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "bell")
                            .foregroundColor(.black)
                            .font(.system(size: 22))
                    }
                }
            }
            .task {
                await loadFeed()
            }
        }
    }

    private func loadFeed() async {
        isLoading = true
        error = nil

        // Try real API first
        let service = FeedService()
        do {
            posts = try await service.getFeed(limit: 20)
            isLoading = false
        } catch {
            // If API fails, fall back to mock data for demo
            print("⚠️ Feed API failed: \(error.localizedDescription), using mock data")

            let mockUser = User(
                id: "1",
                username: "Simone Carter",
                displayName: "Simone Carter",
                avatarUrl: nil,
                bio: nil,
                followersCount: 1234,
                followingCount: 567,
                postsCount: 89
            )

            posts = [
                Post(
                    id: "1",
                    author: mockUser,
                    caption: "kyleegigstead Cyborg dreams... 🤖✨",
                    imageUrl: "https://picsum.photos/400/600",
                    likeCount: 0,
                    commentCount: 0,
                    isLiked: false,
                    createdAt: "2025-11-02T10:30:00Z"
                ),
                Post(
                    id: "2",
                    author: mockUser,
                    caption: "Beautiful sunset at the beach today 🌅",
                    imageUrl: "https://picsum.photos/400/601",
                    likeCount: 245,
                    commentCount: 18,
                    isLiked: false,
                    createdAt: "2025-11-02T18:45:00Z"
                ),
                Post(
                    id: "3",
                    author: mockUser,
                    caption: "Morning coffee vibes ☕️ #MondayMotivation",
                    imageUrl: "https://picsum.photos/400/602",
                    likeCount: 89,
                    commentCount: 12,
                    isLiked: true,
                    createdAt: "2025-11-03T08:15:00Z"
                )
            ]

            isLoading = false
        }
    }
}

// MARK: - Poll Section
struct PollSectionView: View {
    @Binding var currentIndex: Int
    let pollData = [
        PollItem(rank: 1, name: "Lucy Liu", company: "Morgan Stanley", votes: 2293),
        PollItem(rank: 2, name: "Sarah Chen", company: "Goldman Sachs", votes: 2156),
        PollItem(rank: 3, name: "Emma Wong", company: "JP Morgan", votes: 2089),
        PollItem(rank: 4, name: "Jessica Kim", company: "HSBC", votes: 1987),
        PollItem(rank: 5, name: "Lisa Park", company: "Citibank", votes: 1876)
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Title
            VStack(spacing: 4) {
                Text("Hottest Banker in H.K.")
                    .font(.custom("Helvetica Neue", size: 22))
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))

                Text("Corporate Poll")
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.medium)
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
            }

            // Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(pollData.enumerated()), id: \.offset) { index, item in
                        PollCard(item: item)
                            .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: 392)

            // Indicators
            HStack(spacing: 6) {
                ForEach(0..<pollData.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.73, green: 0.73, blue: 0.73))
                        .frame(width: 6, height: 6)
                }
            }

            // View More Button
            HStack(spacing: 4) {
                Text("view more")
                    .font(.custom("Helvetica Neue", size: 13))
                    .foregroundColor(Color(red: 0.81, green: 0.13, blue: 0.25))

                Rectangle()
                    .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.5)
                    .frame(width: 58, height: 1)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
    }
}

struct PollItem {
    let rank: Int
    let name: String
    let company: String
    let votes: Int
}

struct PollCard: View {
    let item: PollItem

    var body: some View {
        VStack(spacing: 18) {
            // Image Container
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.5))
                    .frame(height: 274)
                    .cornerRadius(15)
                    .padding(18)
            }
            .frame(height: 304)
            .background(.white)
            .cornerRadius(15)

            // Info Section
            HStack(alignment: .center, spacing: 10) {
                // Rank Badge
                Text("\(item.rank)")
                    .font(.custom("Helvetica Neue", size: 20))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(width: 35, height: 35)
                    .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                    .cornerRadius(6)

                // Name & Company
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.custom("Helvetica Neue", size: 18))
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))

                    Text(item.company)
                        .font(.custom("Helvetica Neue", size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
                }

                Spacer()

                // Vote Count
                Text("\(item.votes)")
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
            }
            .padding(.horizontal, 15)
        }
        .frame(width: 309)
    }
}

// MARK: - Feed Post Card
struct FeedPostCard: View {
    let post: Post
    @State private var isLiked = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.5))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.username)
                        .font(.custom("Helvetica Neue", size: 12))
                        .fontWeight(.medium)
                        .foregroundColor(Color(red: 0.02, green: 0, blue: 0))

                    Text(timeAgo(from: post.createdAt))
                        .font(.custom("Helvetica Neue", size: 8))
                        .fontWeight(.medium)
                        .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                }

                Spacer()

                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Image
            if let imageUrl = post.imageUrl {
                Rectangle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.5))
                    .frame(height: 450)
                    .padding(.top, 12)
            }

            // Action Buttons
            HStack(spacing: 16) {
                // Like
                Button(action: { isLiked.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? .red : .black)
                        Text("\(post.likeCount)")
                            .font(.custom("Inter", size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                }

                // Comment
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "message")
                            .foregroundColor(.black)
                        Text("\(post.commentCount)")
                            .font(.custom("Inter", size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                }

                Spacer()

                // Share
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.black)
                        Text("Share")
                            .font(.custom("Inter", size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Caption
            HStack {
                Text(post.caption)
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                    .lineLimit(2)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Carousel Indicators
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.81, green: 0.13, blue: 0.25))
                    .frame(width: 6, height: 6)

                ForEach(0..<3) { _ in
                    Circle()
                        .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 16)
        }
        .background(.white)
        .cornerRadius(0)
    }

    private func timeAgo(from dateString: String) -> String {
        // Simple time ago implementation
        return "1d"
    }
}

// MARK: - Helper Views
struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Error Loading Feed")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("No Posts")
                .font(.headline)
            Text("Be the first to share something!")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
