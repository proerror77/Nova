import Foundation
import WidgetKit

/// App Group suite name for sharing data between main app and widgets
let appGroupSuiteName = "group.com.app.icered.pro"

/// Data store for sharing widget data via App Groups
final class WidgetDataStore {
    static let shared = WidgetDataStore()

    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: appGroupSuiteName)
    }

    // MARK: - Keys

    private enum Keys {
        static let unreadMessages = "widget.unreadMessages"
        static let latestSender = "widget.latestSender"
        static let latestMessagePreview = "widget.latestMessagePreview"
        static let followers = "widget.followers"
        static let following = "widget.following"
        static let todayLikes = "widget.todayLikes"
        static let todayViews = "widget.todayViews"
        static let newFollowers = "widget.newFollowers"
        static let newLikes = "widget.newLikes"
        static let newComments = "widget.newComments"
        static let mentions = "widget.mentions"
        static let topPosts = "widget.topPosts"
        static let aliceSuggestion = "widget.aliceSuggestion"
        static let lastUpdate = "widget.lastUpdate"
    }

    // MARK: - Unread Messages

    var unreadMessagesCount: Int {
        get { defaults?.integer(forKey: Keys.unreadMessages) ?? 0 }
        set {
            defaults?.set(newValue, forKey: Keys.unreadMessages)
            reloadWidgets(kind: "UnreadMessagesWidget")
        }
    }

    var latestSender: String? {
        get { defaults?.string(forKey: Keys.latestSender) }
        set { defaults?.set(newValue, forKey: Keys.latestSender) }
    }

    var latestMessagePreview: String? {
        get { defaults?.string(forKey: Keys.latestMessagePreview) }
        set { defaults?.set(newValue, forKey: Keys.latestMessagePreview) }
    }

    func updateUnreadMessages(count: Int, latestSender: String?, preview: String?) {
        defaults?.set(count, forKey: Keys.unreadMessages)
        defaults?.set(latestSender, forKey: Keys.latestSender)
        defaults?.set(preview, forKey: Keys.latestMessagePreview)
        reloadWidgets(kind: "UnreadMessagesWidget")
    }

    // MARK: - Profile Stats

    var followers: Int {
        get { defaults?.integer(forKey: Keys.followers) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.followers) }
    }

    var following: Int {
        get { defaults?.integer(forKey: Keys.following) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.following) }
    }

    var todayLikes: Int {
        get { defaults?.integer(forKey: Keys.todayLikes) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.todayLikes) }
    }

    var todayViews: Int {
        get { defaults?.integer(forKey: Keys.todayViews) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.todayViews) }
    }

    func updateProfileStats(followers: Int, following: Int, todayLikes: Int, todayViews: Int) {
        defaults?.set(followers, forKey: Keys.followers)
        defaults?.set(following, forKey: Keys.following)
        defaults?.set(todayLikes, forKey: Keys.todayLikes)
        defaults?.set(todayViews, forKey: Keys.todayViews)
        reloadWidgets(kind: "ProfileStatsWidget")
    }

    // MARK: - Activity Summary

    var newFollowers: Int {
        get { defaults?.integer(forKey: Keys.newFollowers) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.newFollowers) }
    }

    var newLikes: Int {
        get { defaults?.integer(forKey: Keys.newLikes) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.newLikes) }
    }

    var newComments: Int {
        get { defaults?.integer(forKey: Keys.newComments) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.newComments) }
    }

    var mentions: Int {
        get { defaults?.integer(forKey: Keys.mentions) ?? 0 }
        set { defaults?.set(newValue, forKey: Keys.mentions) }
    }

    func updateActivitySummary(newFollowers: Int, newLikes: Int, newComments: Int, mentions: Int) {
        defaults?.set(newFollowers, forKey: Keys.newFollowers)
        defaults?.set(newLikes, forKey: Keys.newLikes)
        defaults?.set(newComments, forKey: Keys.newComments)
        defaults?.set(mentions, forKey: Keys.mentions)
        reloadWidgets(kind: "ActivitySummaryWidget")
    }

    // MARK: - Feed Highlights

    func saveTopPosts(_ posts: [WidgetPostSnapshot]) {
        if let data = try? JSONEncoder().encode(posts) {
            defaults?.set(data, forKey: Keys.topPosts)
            reloadWidgets(kind: "FeedHighlightsWidget")
        }
    }

    func getTopPosts() -> [WidgetPostSnapshot] {
        guard let data = defaults?.data(forKey: Keys.topPosts),
              let posts = try? JSONDecoder().decode([WidgetPostSnapshot].self, from: data) else {
            return []
        }
        return posts
    }

    // MARK: - Alice Suggestion

    var aliceSuggestion: String {
        get { defaults?.string(forKey: Keys.aliceSuggestion) ?? "Ask Alice anything..." }
        set {
            defaults?.set(newValue, forKey: Keys.aliceSuggestion)
            reloadWidgets(kind: "AliceQuickWidget")
        }
    }

    // MARK: - Last Update

    var lastUpdate: Date {
        get { defaults?.object(forKey: Keys.lastUpdate) as? Date ?? Date() }
        set { defaults?.set(newValue, forKey: Keys.lastUpdate) }
    }

    // MARK: - Widget Reload

    private func reloadWidgets(kind: String) {
        defaults?.set(Date(), forKey: Keys.lastUpdate)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    func reloadAllWidgets() {
        defaults?.set(Date(), forKey: Keys.lastUpdate)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Widget Data Models

/// Lightweight post snapshot for widgets
struct WidgetPostSnapshot: Codable, Identifiable {
    let id: String
    let authorName: String
    let authorAvatar: String?
    let content: String
    let likeCount: Int
    let commentCount: Int
    let thumbnailUrl: String?
    let createdAt: Date
}
