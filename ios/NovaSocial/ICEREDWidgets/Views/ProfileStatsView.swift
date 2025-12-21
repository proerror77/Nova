import SwiftUI
import WidgetKit

struct ProfileStatsWidgetView: View {
    var entry: ProfileStatsEntry
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
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Spacer()
            }

            Spacer()

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text(formatNumber(entry.followers))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Followers")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    Text(formatNumber(entry.following))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Following")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text("Profile Stats")
                        .font(.headline)
                }
                Text("Today's Activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 24) {
                statColumn(value: entry.followers, label: "Followers", icon: "person.2.fill")
                statColumn(value: entry.following, label: "Following", icon: "heart.fill")
                statColumn(value: entry.todayLikes, label: "Likes", icon: "hand.thumbsup.fill")
                statColumn(value: entry.todayViews, label: "Views", icon: "eye.fill")
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func statColumn(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.red)
            Text(formatNumber(value))
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

struct ProfileStatsWidget: Widget {
    let kind: String = "ProfileStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProfileStatsProvider()) { entry in
            ProfileStatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Profile Stats")
        .description("View your follower count and today's engagement stats.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    ProfileStatsWidget()
} timeline: {
    ProfileStatsEntry.placeholder
}

#Preview(as: .systemMedium) {
    ProfileStatsWidget()
} timeline: {
    ProfileStatsEntry.placeholder
}
