import WidgetKit
import Foundation

// MARK: - Unread Messages Entry

struct UnreadMessagesEntry: TimelineEntry {
    let date: Date
    let unreadCount: Int
    let latestSender: String?
    let latestPreview: String?

    static var placeholder: UnreadMessagesEntry {
        UnreadMessagesEntry(
            date: Date(),
            unreadCount: 3,
            latestSender: "Alice",
            latestPreview: "Hey! Check this out..."
        )
    }

    static var empty: UnreadMessagesEntry {
        UnreadMessagesEntry(
            date: Date(),
            unreadCount: 0,
            latestSender: nil,
            latestPreview: nil
        )
    }
}

// MARK: - Profile Stats Entry

struct ProfileStatsEntry: TimelineEntry {
    let date: Date
    let followers: Int
    let following: Int
    let todayLikes: Int
    let todayViews: Int

    static var placeholder: ProfileStatsEntry {
        ProfileStatsEntry(
            date: Date(),
            followers: 1234,
            following: 567,
            todayLikes: 89,
            todayViews: 456
        )
    }

    static var empty: ProfileStatsEntry {
        ProfileStatsEntry(
            date: Date(),
            followers: 0,
            following: 0,
            todayLikes: 0,
            todayViews: 0
        )
    }
}

// MARK: - Activity Summary Entry

struct ActivitySummaryEntry: TimelineEntry {
    let date: Date
    let newFollowers: Int
    let newLikes: Int
    let newComments: Int
    let mentions: Int

    var totalActivity: Int {
        newFollowers + newLikes + newComments + mentions
    }

    static var placeholder: ActivitySummaryEntry {
        ActivitySummaryEntry(
            date: Date(),
            newFollowers: 12,
            newLikes: 45,
            newComments: 8,
            mentions: 3
        )
    }

    static var empty: ActivitySummaryEntry {
        ActivitySummaryEntry(
            date: Date(),
            newFollowers: 0,
            newLikes: 0,
            newComments: 0,
            mentions: 0
        )
    }
}

// MARK: - Feed Highlights Entry

struct FeedHighlightsEntry: TimelineEntry {
    let date: Date
    let topPosts: [WidgetPostSnapshot]
    let unreadCount: Int

    static var placeholder: FeedHighlightsEntry {
        FeedHighlightsEntry(
            date: Date(),
            topPosts: [
                WidgetPostSnapshot(
                    id: "1",
                    authorName: "proerror",
                    authorAvatar: nil,
                    content: "Check out this amazing view!",
                    likeCount: 234,
                    commentCount: 45,
                    thumbnailUrl: nil,
                    createdAt: Date()
                ),
                WidgetPostSnapshot(
                    id: "2",
                    authorName: "alice",
                    authorAvatar: nil,
                    content: "New feature announcement...",
                    likeCount: 189,
                    commentCount: 32,
                    thumbnailUrl: nil,
                    createdAt: Date().addingTimeInterval(-3600)
                )
            ],
            unreadCount: 5
        )
    }

    static var empty: FeedHighlightsEntry {
        FeedHighlightsEntry(
            date: Date(),
            topPosts: [],
            unreadCount: 0
        )
    }
}

// MARK: - Alice Quick Entry

struct AliceQuickEntry: TimelineEntry {
    let date: Date
    let suggestion: String
    let greeting: String

    static var placeholder: AliceQuickEntry {
        AliceQuickEntry(
            date: Date(),
            suggestion: "What would you like to know today?",
            greeting: "Good morning!"
        )
    }

    static var empty: AliceQuickEntry {
        AliceQuickEntry(
            date: Date(),
            suggestion: "Ask Alice anything...",
            greeting: greeting(for: Date())
        )
    }

    static func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning!"
        case 12..<17: return "Good afternoon!"
        case 17..<21: return "Good evening!"
        default: return "Hello!"
        }
    }
}
