import SwiftUI
import WidgetKit

struct ActivitySummaryWidgetView: View {
    var entry: ActivitySummaryEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Spacer()
                if entry.totalActivity > 0 {
                    Text("\(entry.totalActivity)")
                        .font(.title)
                        .fontWeight(.bold)
                }
            }

            Spacer()

            if entry.totalActivity > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    if entry.newFollowers > 0 {
                        activityRow(icon: "person.badge.plus", text: "+\(entry.newFollowers) followers")
                    }
                    if entry.newLikes > 0 {
                        activityRow(icon: "heart.fill", text: "+\(entry.newLikes) likes")
                    }
                    if entry.newComments > 0 {
                        activityRow(icon: "bubble.left.fill", text: "+\(entry.newComments) comments")
                    }
                }
            } else {
                Text("No new activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text("Activity")
                        .font(.headline)
                }

                Text(entry.totalActivity > 0 ? "\(entry.totalActivity) new" : "All caught up!")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Spacer()

            HStack(spacing: 20) {
                activityStat(value: entry.newFollowers, label: "Followers", icon: "person.badge.plus")
                activityStat(value: entry.newLikes, label: "Likes", icon: "heart.fill")
                activityStat(value: entry.newComments, label: "Comments", icon: "bubble.left.fill")
                activityStat(value: entry.mentions, label: "Mentions", icon: "at")
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func activityRow(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.red)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func activityStat(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(value > 0 ? .red : .secondary)
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ActivitySummaryWidget: Widget {
    let kind: String = "ActivitySummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActivitySummaryProvider()) { entry in
            ActivitySummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Activity Summary")
        .description("See your latest followers, likes, comments, and mentions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    ActivitySummaryWidget()
} timeline: {
    ActivitySummaryEntry.placeholder
    ActivitySummaryEntry.empty
}

#Preview(as: .systemMedium) {
    ActivitySummaryWidget()
} timeline: {
    ActivitySummaryEntry.placeholder
}
