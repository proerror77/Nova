import SwiftUI
import WidgetKit

struct UnreadMessagesWidgetView: View {
    var entry: UnreadMessagesEntry
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
                Image(systemName: "message.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Spacer()
                if entry.unreadCount > 0 {
                    Text("\(entry.unreadCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            if let sender = entry.latestSender {
                Text(sender)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            if let preview = entry.latestPreview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if entry.unreadCount == 0 {
                Text("No new messages")
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
                    Image(systemName: "message.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text("Messages")
                        .font(.headline)
                }

                if entry.unreadCount > 0 {
                    Text("\(entry.unreadCount) unread")
                        .font(.title2)
                        .fontWeight(.bold)
                } else {
                    Text("All caught up!")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let sender = entry.latestSender, let preview = entry.latestPreview {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(sender)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: 140)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct UnreadMessagesWidget: Widget {
    let kind: String = "UnreadMessagesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UnreadMessagesProvider()) { entry in
            UnreadMessagesWidgetView(entry: entry)
        }
        .configurationDisplayName("Unread Messages")
        .description("See your unread message count and latest message preview.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    UnreadMessagesWidget()
} timeline: {
    UnreadMessagesEntry.placeholder
    UnreadMessagesEntry.empty
}

#Preview(as: .systemMedium) {
    UnreadMessagesWidget()
} timeline: {
    UnreadMessagesEntry.placeholder
}
