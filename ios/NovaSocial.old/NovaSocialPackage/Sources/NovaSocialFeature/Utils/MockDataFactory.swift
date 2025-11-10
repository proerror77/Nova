import Foundation

/// Factory providing mock data for development and testing fallbacks
enum MockDataFactory {
    // MARK: - Mock Users

    private static let johnDoe = User(
        id: "user_001",
        username: "john_doe",
        displayName: "John Doe",
        avatarUrl: nil,
        bio: "Tech enthusiast and developer",
        followersCount: 1250,
        followingCount: 387,
        postsCount: 45
    )

    private static let janeSmith = User(
        id: "user_002",
        username: "jane_smith",
        displayName: "Jane Smith",
        avatarUrl: nil,
        bio: "Designer and creative thinker",
        followersCount: 2100,
        followingCount: 512,
        postsCount: 78
    )

    private static let mikeWilson = User(
        id: "user_003",
        username: "mike_wilson",
        displayName: "Mike Wilson",
        avatarUrl: nil,
        bio: "Photography and travel",
        followersCount: 3500,
        followingCount: 289,
        postsCount: 156
    )

    private static let sarahJones = User(
        id: "user_004",
        username: "sarah_jones",
        displayName: "Sarah Jones",
        avatarUrl: nil,
        bio: "Product manager and startup founder",
        followersCount: 1890,
        followingCount: 612,
        postsCount: 92
    )

    private static let alexBrown = User(
        id: "user_005",
        username: "alex_brown",
        displayName: "Alex Brown",
        avatarUrl: nil,
        bio: "Writer and content creator",
        followersCount: 4200,
        followingCount: 423,
        postsCount: 203
    )

    static let mockUsers = [johnDoe, janeSmith, mikeWilson, sarahJones, alexBrown]

    // MARK: - Mock Posts

    static let mockPosts = [
        Post(
            id: "post_001",
            author: johnDoe,
            caption: "Just launched my new project! Excited to share it with everyone. Check it out and let me know what you think.",
            imageUrl: nil,
            likeCount: 234,
            commentCount: 12,
            isLiked: false,
            createdAt: "2024-01-15T10:30:00Z"
        ),
        Post(
            id: "post_002",
            author: janeSmith,
            caption: "Design thinking workshop was amazing today. Learned so much from brilliant minds in the community!",
            imageUrl: nil,
            likeCount: 456,
            commentCount: 34,
            isLiked: true,
            createdAt: "2024-01-14T14:20:00Z"
        ),
        Post(
            id: "post_003",
            author: mikeWilson,
            caption: "Sunrise at the mountains. Nothing beats a fresh morning in nature.",
            imageUrl: nil,
            likeCount: 789,
            commentCount: 56,
            isLiked: false,
            createdAt: "2024-01-14T08:45:00Z"
        ),
        Post(
            id: "post_004",
            author: sarahJones,
            caption: "Excited to announce the beta launch of our new product! We've been working hard on this for months.",
            imageUrl: nil,
            likeCount: 567,
            commentCount: 89,
            isLiked: true,
            createdAt: "2024-01-13T16:00:00Z"
        ),
        Post(
            id: "post_005",
            author: alexBrown,
            caption: "New blog post is live! Writing about the future of social media and how technology shapes our connections.",
            imageUrl: nil,
            likeCount: 345,
            commentCount: 23,
            isLiked: false,
            createdAt: "2024-01-13T12:15:00Z"
        ),
        Post(
            id: "post_006",
            author: janeSmith,
            caption: "Color palette inspiration from today's walk in the park. Nature is the best designer.",
            imageUrl: nil,
            likeCount: 612,
            commentCount: 45,
            isLiked: true,
            createdAt: "2024-01-12T17:30:00Z"
        )
    ]

    // MARK: - Mock Conversations

    static let mockConversations = [
        Conversation(
            id: "conv_001",
            name: "John & Jane",
            participantCount: 2,
            lastMessage: "That sounds great! Let's meet up soon.",
            lastMessageAt: "2024-01-15T09:20:00Z",
            lastMessageSenderName: "Jane Smith",
            unreadCount: 2,
            isGroup: false,
            createdAt: "2023-12-01T10:00:00Z",
            participants: [johnDoe, janeSmith]
        ),
        Conversation(
            id: "conv_002",
            name: "Design Team",
            participantCount: 4,
            lastMessage: "The new mockups look amazing!",
            lastMessageAt: "2024-01-15T08:45:00Z",
            lastMessageSenderName: "Sarah Jones",
            unreadCount: 5,
            isGroup: true,
            createdAt: "2023-11-15T14:30:00Z",
            participants: [janeSmith, sarahJones, mikeWilson, alexBrown]
        ),
        Conversation(
            id: "conv_003",
            name: "Mike & Alex",
            participantCount: 2,
            lastMessage: "See you at the event tomorrow!",
            lastMessageAt: "2024-01-14T19:10:00Z",
            lastMessageSenderName: "Alex Brown",
            unreadCount: 0,
            isGroup: false,
            createdAt: "2023-10-20T11:00:00Z",
            participants: [mikeWilson, alexBrown]
        )
    ]

    // MARK: - Mock Notifications

    static let mockNotifications = [
        Notification(
            id: "notif_001",
            userId: "current_user",
            actionType: "like",
            targetId: "post_001",
            timestamp: "2024-01-15T10:45:00Z",
            actor: janeSmith
        ),
        Notification(
            id: "notif_002",
            userId: "current_user",
            actionType: "comment",
            targetId: "post_002",
            timestamp: "2024-01-15T09:30:00Z",
            actor: mikeWilson
        ),
        Notification(
            id: "notif_003",
            userId: "current_user",
            actionType: "follow",
            targetId: "user_001",
            timestamp: "2024-01-14T18:20:00Z",
            actor: sarahJones
        ),
        Notification(
            id: "notif_004",
            userId: "current_user",
            actionType: "like",
            targetId: "post_004",
            timestamp: "2024-01-14T15:00:00Z",
            actor: alexBrown
        ),
        Notification(
            id: "notif_005",
            userId: "current_user",
            actionType: "comment",
            targetId: "post_005",
            timestamp: "2024-01-13T13:45:00Z",
            actor: johnDoe
        )
    ]

    // MARK: - Helper Methods

    /// Returns a random user from the mock data
    static func randomUser() -> User {
        mockUsers.randomElement() ?? johnDoe
    }

    /// Returns a random post from the mock data
    static func randomPost() -> Post {
        mockPosts.randomElement() ?? mockPosts[0]
    }
}
