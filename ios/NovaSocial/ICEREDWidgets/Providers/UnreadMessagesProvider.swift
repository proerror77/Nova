import WidgetKit
import Foundation

struct UnreadMessagesProvider: TimelineProvider {
    private let dataStore = WidgetDataStore.shared

    func placeholder(in context: Context) -> UnreadMessagesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UnreadMessagesEntry) -> Void) {
        let entry = UnreadMessagesEntry(
            date: Date(),
            unreadCount: dataStore.unreadMessagesCount,
            latestSender: dataStore.latestSender,
            latestPreview: dataStore.latestMessagePreview
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UnreadMessagesEntry>) -> Void) {
        let entry = UnreadMessagesEntry(
            date: Date(),
            unreadCount: dataStore.unreadMessagesCount,
            latestSender: dataStore.latestSender,
            latestPreview: dataStore.latestMessagePreview
        )

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
