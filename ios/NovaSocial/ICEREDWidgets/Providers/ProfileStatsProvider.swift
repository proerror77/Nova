import WidgetKit
import Foundation

struct ProfileStatsProvider: TimelineProvider {
    private let dataStore = WidgetDataStore.shared

    func placeholder(in context: Context) -> ProfileStatsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ProfileStatsEntry) -> Void) {
        let entry = ProfileStatsEntry(
            date: Date(),
            followers: dataStore.followers,
            following: dataStore.following,
            todayLikes: dataStore.todayLikes,
            todayViews: dataStore.todayViews
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProfileStatsEntry>) -> Void) {
        let entry = ProfileStatsEntry(
            date: Date(),
            followers: dataStore.followers,
            following: dataStore.following,
            todayLikes: dataStore.todayLikes,
            todayViews: dataStore.todayViews
        )

        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
