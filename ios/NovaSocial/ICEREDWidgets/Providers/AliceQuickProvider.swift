import WidgetKit
import Foundation

struct AliceQuickProvider: TimelineProvider {
    private let dataStore = WidgetDataStore.shared

    func placeholder(in context: Context) -> AliceQuickEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (AliceQuickEntry) -> Void) {
        let entry = AliceQuickEntry(
            date: Date(),
            suggestion: dataStore.aliceSuggestion,
            greeting: AliceQuickEntry.greeting(for: Date())
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AliceQuickEntry>) -> Void) {
        var entries: [AliceQuickEntry] = []
        let currentDate = Date()
        let suggestion = dataStore.aliceSuggestion

        // Create entries for the next 4 hours (greeting changes)
        for hourOffset in 0..<4 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = AliceQuickEntry(
                date: entryDate,
                suggestion: suggestion,
                greeting: AliceQuickEntry.greeting(for: entryDate)
            )
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}
