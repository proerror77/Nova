import Foundation
import SwiftUI

// MARK: - Preview Data

/// Centralized mock data for SwiftUI previews
/// All preview data is accessible via PreviewData namespace
enum PreviewData {

    // MARK: - Users

    enum Users {
        /// Sample current user (logged in)
        static let currentUser = UserProfile(
            id: "preview-user-001",
            username: "johndoe",
            email: "john@example.com",
            displayName: "John Doe",
            bio: "iOS Developer | SwiftUI Enthusiast | Coffee Lover ☕️",
            avatarUrl: "https://picsum.photos/200",
            coverUrl: "https://picsum.photos/800/300",
            website: "https://johndoe.dev",
            location: "San Francisco, CA",
            isVerified: true,
            isPrivate: false,
            isBanned: false,
            followerCount: 12500,
            followingCount: 890,
            postCount: 156,
            createdAt: Int64(Date().timeIntervalSince1970 - 86400 * 365),
            updatedAt: Int64(Date().timeIntervalSince1970),
            deletedAt: nil,
            firstName: "John",
            lastName: "Doe",
            dateOfBirth: "1995-06-15",
            gender: .male
        )

        /// Sample user without verification
        static let regularUser = UserProfile(
            id: "preview-user-002",
            username: "janedoe",
            email: "jane@example.com",
            displayName: "Jane Doe",
            bio: "Photographer | Travel Enthusiast",
            avatarUrl: "https://picsum.photos/201",
            coverUrl: nil,
            website: nil,
            location: "New York, NY",
            isVerified: false,
            isPrivate: false,
            isBanned: false,
            followerCount: 3420,
            followingCount: 567,
            postCount: 89,
            createdAt: Int64(Date().timeIntervalSince1970 - 86400 * 180),
            updatedAt: Int64(Date().timeIntervalSince1970),
            deletedAt: nil
        )

        /// Sample private user
        static let privateUser = UserProfile(
            id: "preview-user-003",
            username: "privateaccount",
            email: nil,
            displayName: "Private User",
            bio: "🔒 Private Account",
            avatarUrl: "https://picsum.photos/202",
            coverUrl: nil,
            website: nil,
            location: nil,
            isVerified: false,
            isPrivate: true,
            isBanned: false,
            followerCount: 150,
            followingCount: 45,
            postCount: 23,
            createdAt: Int64(Date().timeIntervalSince1970 - 86400 * 90),
            updatedAt: Int64(Date().timeIntervalSince1970),
            deletedAt: nil
        )

        /// Guest user
        static let guestUser = UserProfile(
            id: "guest",
            username: "Guest",
            email: nil,
            displayName: "Guest User",
            bio: nil,
            avatarUrl: nil,
            coverUrl: nil,
            website: nil,
            location: nil,
            isVerified: false,
            isPrivate: false,
            isBanned: false,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )

        /// Array of sample users for lists
        static let sampleUsers: [UserProfile] = [
            currentUser,
            regularUser,
            privateUser,
            UserProfile(id: "preview-user-004", username: "alice_wonder", displayName: "Alice Wonder", avatarUrl: "https://picsum.photos/203", isVerified: true, followerCount: 8900, followingCount: 234, postCount: 67),
            UserProfile(id: "preview-user-005", username: "bob_builder", displayName: "Bob Builder", avatarUrl: "https://picsum.photos/204", isVerified: false, followerCount: 2100, followingCount: 456, postCount: 34),
            UserProfile(id: "preview-user-006", username: "carol_smith", displayName: "Carol Smith", avatarUrl: "https://picsum.photos/205", isVerified: false, followerCount: 567, followingCount: 123, postCount: 12),
        ]
    }

    // MARK: - Posts

    enum Posts {
        /// Sample post with image
        static let imagePost = Post(
            id: "preview-post-001",
            authorId: Users.currentUser.id,
            content: "Beautiful sunset at the beach! 🌅 #sunset #beach #photography",
            title: "Golden Hour",
            createdAt: Int64(Date().timeIntervalSince1970 - 3600),
            updatedAt: Int64(Date().timeIntervalSince1970 - 3600),
            status: "published",
            mediaUrls: ["https://picsum.photos/600/400"],
            mediaType: "image",
            likeCount: 156,
            commentCount: 23,
            shareCount: 8,
            bookmarkCount: nil,
            authorUsername: Users.currentUser.username,
            authorDisplayName: Users.currentUser.displayName,
            authorAvatarUrl: Users.currentUser.avatarUrl,
            location: "Malibu, California",
            tags: ["sunset", "beach", "photography"]
        )

        /// Sample post with multiple images
        static let multiImagePost = Post(
            id: "preview-post-002",
            authorId: Users.regularUser.id,
            content: "My travel diary from Japan 🇯🇵 Swipe to see more!",
            title: "Japan Travel Diary",
            createdAt: Int64(Date().timeIntervalSince1970 - 7200),
            updatedAt: Int64(Date().timeIntervalSince1970 - 7200),
            status: "published",
            mediaUrls: [
                "https://picsum.photos/601/400",
                "https://picsum.photos/602/400",
                "https://picsum.photos/603/400"
            ],
            mediaType: "image",
            likeCount: 342,
            commentCount: 56,
            shareCount: 21,
            bookmarkCount: nil,
            authorUsername: Users.regularUser.username,
            authorDisplayName: Users.regularUser.displayName,
            authorAvatarUrl: Users.regularUser.avatarUrl,
            location: "Tokyo, Japan",
            tags: ["travel", "japan", "tokyo", "diary"]
        )

        /// Sample text-only post
        static let textPost = Post(
            id: "preview-post-003",
            authorId: Users.currentUser.id,
            content: "Just finished reading an amazing book about SwiftUI! Highly recommend it for anyone looking to level up their iOS development skills. 📚",
            title: "Book Recommendation",
            createdAt: Int64(Date().timeIntervalSince1970 - 86400),
            updatedAt: Int64(Date().timeIntervalSince1970 - 86400),
            status: "published",
            mediaUrls: nil,
            mediaType: nil,
            likeCount: 78,
            commentCount: 12,
            shareCount: 3,
            bookmarkCount: nil,
            authorUsername: Users.currentUser.username,
            authorDisplayName: Users.currentUser.displayName,
            authorAvatarUrl: Users.currentUser.avatarUrl,
            location: nil,
            tags: ["SwiftUI", "iOS", "programming", "books"]
        )

        /// Array of sample posts for feeds
        static let samplePosts: [Post] = [
            imagePost,
            multiImagePost,
            textPost,
            Post(id: "preview-post-004", authorId: "preview-user-004", content: "Working on something exciting! Stay tuned 🚀", title: "Sneak Peek", createdAt: Int64(Date().timeIntervalSince1970 - 3600 * 5), updatedAt: Int64(Date().timeIntervalSince1970 - 3600 * 5), status: "published", mediaUrls: ["https://picsum.photos/604/400"], mediaType: "image", likeCount: 234, commentCount: 45, shareCount: 12, bookmarkCount: nil, authorUsername: "alice_wonder", authorDisplayName: "Alice Wonder", authorAvatarUrl: "https://picsum.photos/203", location: "San Francisco, USA", tags: ["startup", "tech"]),
            Post(id: "preview-post-005", authorId: "preview-user-005", content: "Morning coffee ☕️", title: "Coffee Time", createdAt: Int64(Date().timeIntervalSince1970 - 3600 * 8), updatedAt: Int64(Date().timeIntervalSince1970 - 3600 * 8), status: "published", mediaUrls: ["https://picsum.photos/605/400"], mediaType: "image", likeCount: 89, commentCount: 7, shareCount: 2, bookmarkCount: nil, authorUsername: "bob_builder", authorDisplayName: "Bob Builder", authorAvatarUrl: "https://picsum.photos/204", location: "Seattle, USA", tags: ["coffee", "morning"]),
            Post(id: "preview-post-006", authorId: "preview-user-006", content: "Just hit a new personal record at the gym! 💪", title: "Personal Best", createdAt: Int64(Date().timeIntervalSince1970 - 86400 * 2), updatedAt: Int64(Date().timeIntervalSince1970 - 86400 * 2), status: "published", mediaUrls: nil, mediaType: nil, likeCount: 156, commentCount: 34, shareCount: 5, bookmarkCount: nil, authorUsername: "carol_smith", authorDisplayName: "Carol Smith", authorAvatarUrl: "https://picsum.photos/205", location: nil, tags: ["fitness", "gym", "workout"]),
        ]
    }

    // MARK: - Feed Posts (for HomeView)

    enum Feed {
        /// Sample feed posts with author info
        static let sampleFeedPosts: [FeedPost] = [
            FeedPost(
                id: "feed-001",
                authorId: Users.currentUser.id,
                authorName: Users.currentUser.displayName ?? Users.currentUser.username,
                authorAvatar: Users.currentUser.avatarUrl,
                content: "Beautiful sunset at the beach! 🌅 #sunset #beach",
                mediaUrls: ["https://picsum.photos/600/400"],
                mediaType: .image,
                createdAt: Date().addingTimeInterval(-3600),
                likeCount: 156,
                commentCount: 23,
                shareCount: 8,
                isLiked: false,
                isBookmarked: false,
                location: "Malibu, California",
                tags: ["sunset", "beach", "photography"]
            ),
            FeedPost(
                id: "feed-002",
                authorId: Users.regularUser.id,
                authorName: Users.regularUser.displayName ?? Users.regularUser.username,
                authorAvatar: Users.regularUser.avatarUrl,
                content: "Just launched my new app! Check it out 🚀",
                mediaUrls: ["https://picsum.photos/601/400"],
                mediaType: .image,
                createdAt: Date().addingTimeInterval(-7200),
                likeCount: 342,
                commentCount: 56,
                shareCount: 21,
                isLiked: true,
                isBookmarked: false,
                location: "San Francisco, USA",
                tags: ["startup", "tech", "app"]
            ),
            FeedPost(
                id: "feed-003",
                authorId: "preview-user-004",
                authorName: "Alice Wonder",
                authorAvatar: "https://picsum.photos/203",
                content: "Working from my favorite cafe today ☕️",
                mediaUrls: ["https://picsum.photos/602/400"],
                mediaType: .image,
                createdAt: Date().addingTimeInterval(-10800),
                likeCount: 89,
                commentCount: 12,
                shareCount: 3,
                isLiked: false,
                isBookmarked: true,
                location: "Seattle, USA",
                tags: ["coffee", "cafe", "work"]
            ),
        ]
    }

    // MARK: - Comments

    enum Comments {
        static let sampleComments: [SocialComment] = [
            SocialComment(
                id: "comment-001",
                userId: Users.regularUser.id,
                postId: Posts.imagePost.id,
                content: "Amazing shot! 📸",
                parentCommentId: nil,
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1800)),
                authorUsername: Users.regularUser.username,
                authorDisplayName: Users.regularUser.displayName,
                authorAvatarUrl: Users.regularUser.avatarUrl,
                likeCount: 5,
                isLikedByViewer: false
            ),
            SocialComment(
                id: "comment-002",
                userId: "preview-user-004",
                postId: Posts.imagePost.id,
                content: "Love this! Where was this taken?",
                parentCommentId: nil,
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
                authorUsername: "alice_wonder",
                authorDisplayName: "Alice Wonder",
                authorAvatarUrl: "https://picsum.photos/203",
                likeCount: 2,
                isLikedByViewer: true
            ),
            SocialComment(
                id: "comment-003",
                userId: Users.currentUser.id,
                postId: Posts.imagePost.id,
                content: "Thanks! It was at Malibu Beach 🏖️",
                parentCommentId: "comment-002",
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1200)),
                authorUsername: Users.currentUser.username,
                authorDisplayName: Users.currentUser.displayName,
                authorAvatarUrl: Users.currentUser.avatarUrl,
                likeCount: 0,
                isLikedByViewer: false
            ),
        ]
    }

    // MARK: - Conversations

    enum Conversations {
        static let sampleConversations: [Conversation] = [
            Conversation(
                id: "conv-001",
                type: .direct,
                name: nil,
                createdAt: Date().addingTimeInterval(-86400 * 7),
                updatedAt: Date().addingTimeInterval(-300),
                members: [
                    ConversationMember(userId: Users.currentUser.id, username: Users.currentUser.username),
                    ConversationMember(userId: Users.regularUser.id, username: Users.regularUser.username)
                ],
                unreadCount: 2
            ),
            Conversation(
                id: "conv-002",
                type: .group,
                name: "Dev Team",
                createdAt: Date().addingTimeInterval(-86400 * 30),
                updatedAt: Date().addingTimeInterval(-3600),
                members: [
                    ConversationMember(userId: Users.currentUser.id, username: Users.currentUser.username, role: .admin),
                    ConversationMember(userId: "preview-user-004", username: "alice_wonder"),
                    ConversationMember(userId: "preview-user-005", username: "bob_builder")
                ],
                unreadCount: 0,
                avatarUrl: "https://picsum.photos/206"
            ),
        ]
    }

    // MARK: - Notifications

    enum Notifications {
        static let sampleNotifications: [NotificationItem] = [
            NotificationItem(
                id: "notif-001",
                type: .like,
                message: "Jane Doe liked your post",
                timestamp: Date().addingTimeInterval(-1800),
                isRead: false,
                relatedUserId: Users.regularUser.id,
                relatedPostId: Posts.imagePost.id,
                relatedCommentId: nil,
                userAvatarUrl: Users.regularUser.avatarUrl,
                userName: Users.regularUser.displayName
            ),
            NotificationItem(
                id: "notif-002",
                type: .comment,
                message: "Alice Wonder commented on your post",
                timestamp: Date().addingTimeInterval(-3600),
                isRead: false,
                relatedUserId: "preview-user-004",
                relatedPostId: Posts.imagePost.id,
                relatedCommentId: "comment-002",
                userAvatarUrl: "https://picsum.photos/203",
                userName: "Alice Wonder"
            ),
            NotificationItem(
                id: "notif-003",
                type: .follow,
                message: "Bob Builder started following you",
                timestamp: Date().addingTimeInterval(-86400),
                isRead: true,
                relatedUserId: "preview-user-005",
                relatedPostId: nil,
                relatedCommentId: nil,
                userAvatarUrl: "https://picsum.photos/204",
                userName: "Bob Builder"
            ),
        ]
    }

    // MARK: - Polls

    enum Polls {
        static let samplePolls: [PollSummary] = [
            PollSummary(
                id: "poll-001",
                title: "Best Programming Language 2025",
                coverImageUrl: "https://picsum.photos/607/300",
                pollType: "ranking",
                status: "active",
                totalVotes: 15234,
                candidateCount: 10,
                topCandidates: [
                    CandidatePreview(id: "c1", name: "Swift", avatarUrl: nil, rank: 1),
                    CandidatePreview(id: "c2", name: "Kotlin", avatarUrl: nil, rank: 2),
                    CandidatePreview(id: "c3", name: "TypeScript", avatarUrl: nil, rank: 3)
                ],
                tags: ["tech", "programming"],
                endsAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 7))
            ),
            PollSummary(
                id: "poll-002",
                title: "Top Travel Destinations",
                coverImageUrl: "https://picsum.photos/608/300",
                pollType: "ranking",
                status: "active",
                totalVotes: 8765,
                candidateCount: 20,
                topCandidates: [
                    CandidatePreview(id: "c4", name: "Japan", avatarUrl: nil, rank: 1),
                    CandidatePreview(id: "c5", name: "Italy", avatarUrl: nil, rank: 2),
                    CandidatePreview(id: "c6", name: "Greece", avatarUrl: nil, rank: 3)
                ],
                tags: ["travel", "lifestyle"],
                endsAt: nil
            ),
        ]
    }

    // MARK: - Channels

    enum Channels {
        static let sampleChannels: [ChannelSummary] = [
            ChannelSummary(id: "ch-001", name: "Fashion", description: "Latest fashion trends", category: "Lifestyle", thumbnailUrl: "https://picsum.photos/609/200", subscriberCount: 125000, isSubscribed: true),
            ChannelSummary(id: "ch-002", name: "Tech", description: "Technology news and updates", category: "Technology", thumbnailUrl: "https://picsum.photos/610/200", subscriberCount: 89000, isSubscribed: false),
            ChannelSummary(id: "ch-003", name: "Travel", description: "Travel inspiration", category: "Lifestyle", thumbnailUrl: "https://picsum.photos/611/200", subscriberCount: 67000, isSubscribed: true),
            ChannelSummary(id: "ch-004", name: "Fitness", description: "Health and fitness tips", category: "Health", thumbnailUrl: "https://picsum.photos/612/200", subscriberCount: 45000, isSubscribed: false),
        ]
    }

    // MARK: - Search Results

    enum Search {
        static let sampleResults: [SearchResult] = [
            .user(id: Users.regularUser.id, username: Users.regularUser.username, displayName: Users.regularUser.displayName ?? Users.regularUser.username, avatarUrl: Users.regularUser.avatarUrl, isVerified: Users.regularUser.safeIsVerified),
            .user(id: "preview-user-004", username: "alice_wonder", displayName: "Alice Wonder", avatarUrl: "https://picsum.photos/203", isVerified: true),
            .post(id: Posts.imagePost.id, content: Posts.imagePost.content, author: Posts.imagePost.authorId, createdAt: Posts.imagePost.createdDate, likeCount: Posts.imagePost.likeCount ?? 0),
            .hashtag(tag: "sunset", postCount: 15234),
            .hashtag(tag: "photography", postCount: 89567),
        ]
    }
}

// MARK: - Preview Environment Setup

extension PreviewData {
    /// Create a configured AuthenticationManager for previews
    @MainActor
    static func createPreviewAuthManager() -> AuthenticationManager {
        let manager = AuthenticationManager.shared
        // Set up mock state
        manager.isAuthenticated = true
        manager.currentUser = Users.currentUser
        return manager
    }
}

// MARK: - View Extension for Preview

extension View {
    /// Apply standard preview configuration
    func previewSetup() -> some View {
        self
            .environmentObject(AuthenticationManager.shared)
            .withFeatureFlags(.preview)
    }

    /// Apply preview with specific user
    func previewSetup(user: UserProfile) -> some View {
        let authManager = AuthenticationManager.shared
        authManager.currentUser = user
        authManager.isAuthenticated = true

        return self
            .environmentObject(authManager)
            .withFeatureFlags(.preview)
    }
}
