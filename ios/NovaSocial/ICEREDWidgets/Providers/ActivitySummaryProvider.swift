import WidgetKit
import Foundation

struct ActivitySummaryProvider: TimelineProvider {
    private let dataStore = WidgetDataStore.shared

    func placeholder(in context: Context) -> ActivitySummaryEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ActivitySummaryEntry) -> Void) {
        let entry = ActivitySummaryEntry(
            date: Date(),
            newFollowers: dataStore.newFollowers,
            newLikes: dataStore.newLikes,
            newComments: dataStore.newComments,
            mentions: dataStore.mentions
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivitySummaryEntry>) -> Void) {
        let entry = ActivitySummaryEntry(
            date: Date(),
            newFollowers: dataStore.newFollowers,
            newLikes: dataStore.newLikes,
            newComments: dataStore.newComments,
            mentions: dataStore.mentions
        )

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
