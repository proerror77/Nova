import SwiftUI
import WidgetKit

struct AliceQuickWidgetView: View {
    var entry: AliceQuickEntry
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
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.red)
                Spacer()
            }

            Spacer()

            Text(entry.greeting)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(entry.suggestion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding()
        .containerBackground(
            LinearGradient(
                colors: [Color.red.opacity(0.1), Color.orange.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.title)
                        .foregroundStyle(.red)
                    Text("Alice")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Text(entry.greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(entry.suggestion)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)

                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                    Text("Tap to ask")
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }
            .frame(maxWidth: 180)
        }
        .padding()
        .containerBackground(
            LinearGradient(
                colors: [Color.red.opacity(0.1), Color.orange.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }
}

struct AliceQuickWidget: Widget {
    let kind: String = "AliceQuickWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AliceQuickProvider()) { entry in
            AliceQuickWidgetView(entry: entry)
        }
        .configurationDisplayName("Alice Quick Access")
        .description("Quick access to Alice AI assistant with smart suggestions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    AliceQuickWidget()
} timeline: {
    AliceQuickEntry.placeholder
}

#Preview(as: .systemMedium) {
    AliceQuickWidget()
} timeline: {
    AliceQuickEntry.placeholder
}
