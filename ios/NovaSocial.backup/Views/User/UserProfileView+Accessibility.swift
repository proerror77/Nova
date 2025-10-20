//
//  UserProfileView+Accessibility.swift
//  NovaSocial
//
//  Created by Nova Team
//  Accessibility support for user profile views
//

import SwiftUI

// MARK: - Profile Header Accessibility

extension View {

    /// Add accessibility support to user profile header
    func profileHeaderAccessibility(
        username: String,
        displayName: String?,
        bio: String?,
        followers: Int,
        following: Int,
        posts: Int,
        isFollowing: Bool,
        isOwnProfile: Bool
    ) -> some View {
        self.accessibilityElement(children: .contain)
            .accessibilityLabel(profileHeaderLabel(
                username: username,
                displayName: displayName,
                bio: bio,
                followers: followers,
                following: following,
                posts: posts,
                isFollowing: isFollowing,
                isOwnProfile: isOwnProfile
            ))
    }

    private func profileHeaderLabel(
        username: String,
        displayName: String?,
        bio: String?,
        followers: Int,
        following: Int,
        posts: Int,
        isFollowing: Bool,
        isOwnProfile: Bool
    ) -> String {
        var parts: [String] = []

        // Name
        if let displayName = displayName {
            parts.append("\(displayName), @\(username)")
        } else {
            parts.append("@\(username)")
        }

        // Bio
        if let bio = bio, !bio.isEmpty {
            parts.append(bio)
        }

        // Stats
        parts.append("\(posts) \(posts == 1 ? "post" : "posts")")
        parts.append("\(followers) \(followers == 1 ? "follower" : "followers")")
        parts.append("Following \(following)")

        // Follow status
        if !isOwnProfile {
            if isFollowing {
                parts.append("You are following this user")
            } else {
                parts.append("You are not following this user")
            }
        } else {
            parts.append("This is your profile")
        }

        return parts.joined(separator: ". ")
    }
}

// MARK: - Profile Avatar

struct AccessibleProfileAvatar: View {

    let imageURL: URL?
    let username: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .empty:
                placeholderAvatar

            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)

            case .failure:
                placeholderAvatar

            @unknown default:
                placeholderAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(.systemGray5), lineWidth: 1))
        .accessibilityLabel("Profile picture for \(username)")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(AccessibilityIdentifiers.Profile.avatarImage)
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray5))

            Image(systemName: "person.fill")
                .font(.system(size: size * 0.5))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Profile Stats

struct ProfileStatsView: View {

    let posts: Int
    let followers: Int
    let following: Int
    let onPostsTap: () -> Void
    let onFollowersTap: () -> Void
    let onFollowingTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            StatButton(
                count: posts,
                label: "Posts",
                action: onPostsTap
            )

            Divider()
                .frame(height: 40)
                .accessibilityHidden(true)

            StatButton(
                count: followers,
                label: "Followers",
                action: onFollowersTap
            )

            Divider()
                .frame(height: 40)
                .accessibilityHidden(true)

            StatButton(
                count: following,
                label: "Following",
                action: onFollowingTap
            )
        }
        .frame(height: 60)
    }
}

private struct StatButton: View {

    let count: Int
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)

                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AccessibilityConstants.minTouchTargetSize)
        }
        .accessibilityLabel("\(count) \(label)")
        .accessibilityHint("Double tap to view \(label.lowercased())")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Follow Button

struct FollowButton: View {

    let isFollowing: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        AccessibleButton(
            isFollowing ? "Following" : "Follow",
            icon: isFollowing ? "checkmark" : "plus",
            style: isFollowing ? .secondary : .primary,
            size: .medium,
            action: {
                action()
                announceFollowAction()
            }
        )
        .loading(isLoading)
        .accessibilityLabel(isFollowing ? "Unfollow" : "Follow")
        .accessibilityHint(isFollowing ? "Double tap to unfollow this user" : "Double tap to follow this user")
        .accessibilityIdentifier(AccessibilityIdentifiers.Profile.followButton)
    }

    private func announceFollowAction() {
        if isFollowing {
            AccessibilityHelper.announce("Unfollowed user")
        } else {
            AccessibilityHelper.announce("Following user")
        }
    }
}

// MARK: - Profile Action Menu

struct ProfileActionMenu: View {

    let isOwnProfile: Bool
    let onEdit: (() -> Void)?
    let onShare: () -> Void
    let onReport: (() -> Void)?
    let onBlock: (() -> Void)?

    var body: some View {
        Menu {
            if isOwnProfile, let onEdit = onEdit {
                Button(action: onEdit) {
                    Label("Edit Profile", systemImage: "pencil")
                }
                .accessibilityLabel("Edit profile")
            }

            Button(action: onShare) {
                Label("Share Profile", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share profile")

            if !isOwnProfile {
                Divider()

                if let onReport = onReport {
                    Button(role: .destructive, action: onReport) {
                        Label("Report User", systemImage: "exclamationmark.triangle")
                    }
                    .accessibilityLabel("Report user")
                }

                if let onBlock = onBlock {
                    Button(role: .destructive, action: onBlock) {
                        Label("Block User", systemImage: "hand.raised")
                    }
                    .accessibilityLabel("Block user")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(
                    width: AccessibilityConstants.minTouchTargetSize,
                    height: AccessibilityConstants.minTouchTargetSize
                )
        }
        .accessibilityLabel("Profile actions")
        .accessibilityHint("Double tap to open actions menu")
    }
}

// MARK: - Profile Tab Selector

struct ProfileTabSelector: View {

    enum Tab: String, CaseIterable {
        case posts = "Posts"
        case media = "Media"
        case likes = "Likes"

        var icon: String {
            switch self {
            case .posts: return "square.grid.3x3"
            case .media: return "play.rectangle"
            case .likes: return "heart"
            }
        }
    }

    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                    announceTabChange(tab: tab)
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: AccessibilityConstants.minTouchTargetSize)
                }
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint("Double tap to switch to \(tab.rawValue.lowercased()) tab")
            }
        }
        .background(Color(.systemBackground))
    }

    private func announceTabChange(tab: Tab) {
        AccessibilityHelper.announce("\(tab.rawValue) tab selected")
    }
}

// MARK: - Profile Loading Skeleton

struct ProfileLoadingView: View {

    var body: some View {
        VStack(spacing: 16) {
            // Avatar skeleton
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 80, height: 80)
                .shimmer()

            // Name skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 120, height: 20)
                .shimmer()

            // Stats skeleton
            HStack(spacing: 40) {
                ForEach(0..<3) { _ in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: 40, height: 20)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 16)
                    }
                    .shimmer()
                }
            }

            // Bio skeleton
            VStack(spacing: 8) {
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 16)
                }
            }
            .padding(.horizontal, 40)
            .shimmer()
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading profile")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Shimmer Effect

extension View {
    func shimmer() -> some View {
        self.overlay(
            GeometryReader { geometry in
                ShimmerView(width: geometry.size.width)
            }
        )
        .clipped()
    }
}

private struct ShimmerView: View {
    let width: CGFloat
    @State private var offset: CGFloat = -200

    var body: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.white.opacity(0.3),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 200)
        .offset(x: offset)
        .onAppear {
            withAnimation(
                Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                offset = width + 200
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#if DEBUG
struct UserProfileAccessibility_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Avatar
            AccessibleProfileAvatar(
                imageURL: nil,
                username: "johndoe",
                size: 80
            )

            // Stats
            ProfileStatsView(
                posts: 42,
                followers: 1234,
                following: 567,
                onPostsTap: { },
                onFollowersTap: { },
                onFollowingTap: { }
            )

            // Follow button
            FollowButton(
                isFollowing: false,
                isLoading: false,
                action: { }
            )

            // Tab selector
            ProfileTabSelector(selectedTab: .constant(.posts))

            // Loading view
            ProfileLoadingView()
                .frame(height: 300)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
