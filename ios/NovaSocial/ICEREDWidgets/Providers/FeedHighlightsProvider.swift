import WidgetKit
import Foundation

struct FeedHighlightsProvider: TimelineProvider {
    private let dataStore = WidgetDataStore.shared

    func placeholder(in context: Context) -> FeedHighlightsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedHighlightsEntry) -> Void) {
        let entry = FeedHighlightsEntry(
            date: Date(),
            topPosts: dataStore.getTopPosts(),
            unreadCount: dataStore.unreadMessagesCount
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedHighlightsEntry>) -> Void) {
        let entry = FeedHighlightsEntry(
            date: Date(),
            topPosts: dataStore.getTopPosts(),
            unreadCount: dataStore.unreadMessagesCount
        )

        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
