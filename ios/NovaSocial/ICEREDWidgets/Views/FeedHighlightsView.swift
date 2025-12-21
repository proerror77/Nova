import SwiftUI
import WidgetKit

struct FeedHighlightsWidgetView: View {
    var entry: FeedHighlightsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("Highlights")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer()

            if let topPost = entry.topPosts.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(topPost.authorName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(topPost.content)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                Text("No highlights yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("Feed Highlights")
                    .font(.headline)
                Spacer()
                if entry.unreadCount > 0 {
                    Text("\(entry.unreadCount) new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.topPosts.isEmpty {
                Spacer()
                Text("No highlights yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(entry.topPosts.prefix(2)) { post in
                        postCard(post)
                    }
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("Feed Highlights")
                    .font(.headline)
                Spacer()
                if entry.unreadCount > 0 {
                    Text("\(entry.unreadCount) new posts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.topPosts.isEmpty {
                Spacer()
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No highlights yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.topPosts.prefix(3)) { post in
                    largePostRow(post)
                    if post.id != entry.topPosts.prefix(3).last?.id {
                        Divider()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func postCard(_ post: WidgetPostSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.authorName)
                .font(.caption)
                .fontWeight(.semibold)
            Text(post.content)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack(spacing: 8) {
                Label("\(post.likeCount)", systemImage: "heart.fill")
                Label("\(post.commentCount)", systemImage: "bubble.left.fill")
            }
            .font(.caption2)
            .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func largePostRow(_ post: WidgetPostSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(post.authorName.prefix(1)).uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(post.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(post.likeCount)", systemImage: "heart.fill")
                    Label("\(post.commentCount)", systemImage: "bubble.left.fill")
                }
                .font(.caption2)
                .foregroundStyle(.red)
            }
        }
    }
}

struct FeedHighlightsWidget: Widget {
    let kind: String = "FeedHighlightsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FeedHighlightsProvider()) { entry in
            FeedHighlightsWidgetView(entry: entry)
        }
        .configurationDisplayName("Feed Highlights")
        .description("See trending posts from your feed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    FeedHighlightsWidget()
} timeline: {
    FeedHighlightsEntry.placeholder
}

#Preview(as: .systemMedium) {
    FeedHighlightsWidget()
} timeline: {
    FeedHighlightsEntry.placeholder
}

#Preview(as: .systemLarge) {
    FeedHighlightsWidget()
} timeline: {
    FeedHighlightsEntry.placeholder
}
