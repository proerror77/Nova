import SwiftUI

// MARK: - Suggested Creators Section

/// A horizontal scrollable section showing recommended creators to follow
/// Used in the Following tab when user doesn't follow many people
struct SuggestedCreatorsSection: View {
    let creators: [RecommendedCreator]
    let onFollow: (String) async -> Void
    let onCreatorTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Suggested for you")
                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                    .foregroundColor(.black)

                Spacer()

                Button(action: {}) {
                    Text("See All")
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(DesignTokens.accentColor)
                }
            }
            .padding(.horizontal, 16)

            // Horizontal scroll of creator cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(creators) { creator in
                        SuggestedCreatorCard(
                            creator: creator,
                            onFollow: { await onFollow(creator.id) },
                            onTap: { onCreatorTap(creator.id) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 16)
        .background(Color.white)
    }
}

// MARK: - Suggested Creator Card

/// A compact card for displaying a suggested creator
struct SuggestedCreatorCard: View {
    let creator: RecommendedCreator
    let onFollow: () async -> Void
    let onTap: () -> Void

    @State private var isFollowing = false
    @State private var isFollowed = false

    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            Button(action: onTap) {
                AvatarView(image: nil, url: creator.avatarUrl, size: 60)
            }

            // Name
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text(creator.displayName)
                        .font(Font.custom("SFProDisplay-Semibold", size: 13.f))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    if creator.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                            .foregroundColor(.blue)
                    }
                }

                Text("@\(creator.username)")
                    .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            // Follower count
            Text("\(formatFollowerCount(creator.followerCount)) followers")
                .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                .foregroundColor(.gray)

            // Follow button
            Button(action: {
                guard !isFollowing && !isFollowed else { return }
                isFollowing = true
                Task {
                    await onFollow()
                    await MainActor.run {
                        isFollowed = true
                        isFollowing = false
                    }
                }
            }) {
                if isFollowing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 70, height: 28)
                } else if isFollowed {
                    Text("Following")
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(.gray)
                        .frame(width: 70, height: 28)
                        .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                        .cornerRadius(14)
                } else {
                    Text("Follow")
                        .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 28)
                        .background(DesignTokens.accentColor)
                        .cornerRadius(14)
                }
            }
            .disabled(isFollowing || isFollowed)
        }
        .frame(width: 100)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(red: 0.98, green: 0.98, blue: 0.98))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.92, green: 0.92, blue: 0.92), lineWidth: 1)
        )
    }

    private func formatFollowerCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Preview

#Preview {
    SuggestedCreatorsSection(
        creators: [
            RecommendedCreator(
                id: "1",
                username: "johndoe",
                displayName: "John Doe",
                avatarUrl: nil,
                bio: "iOS Developer",
                followerCount: 15000,
                isVerified: true,
                relevanceScore: 0.95,
                reason: "Popular in your network"
            ),
            RecommendedCreator(
                id: "2",
                username: "janedoe",
                displayName: "Jane Doe",
                avatarUrl: nil,
                bio: "Designer",
                followerCount: 8500,
                isVerified: false,
                relevanceScore: 0.88,
                reason: nil
            ),
            RecommendedCreator(
                id: "3",
                username: "techguru",
                displayName: "Tech Guru",
                avatarUrl: nil,
                bio: "Tech content",
                followerCount: 125000,
                isVerified: true,
                relevanceScore: 0.92,
                reason: "Trending"
            )
        ],
        onFollow: { _ in },
        onCreatorTap: { _ in }
    )
}
