import SwiftUI
import UIKit

// MARK: - Share Sheet (UIActivityViewController Wrapper)

/// A SwiftUI wrapper for UIActivityViewController to enable native iOS sharing
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let onComplete: ((Bool) -> Void)?

    init(
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        self.excludedActivityTypes = excludedActivityTypes
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )

        controller.excludedActivityTypes = excludedActivityTypes

        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Share Content Builder

/// Helper to build share content from a FeedPost
struct ShareContentBuilder {

    /// Build share items for a post
    /// - Parameters:
    ///   - post: The post to share
    ///   - appName: App name for attribution
    ///   - baseUrl: Base URL for deep links
    /// - Returns: Array of items to share
    static func buildShareItems(
        for post: FeedPost,
        appName: String = "Nova",
        baseUrl: String = "https://nova.social"
    ) -> [Any] {
        var items: [Any] = []

        // 1. Share text content
        let shareText = buildShareText(for: post, appName: appName, baseUrl: baseUrl)
        items.append(shareText)

        // 2. Add post URL for deep linking
        let postUrl = URL(string: "\(baseUrl)/post/\(post.id)")
        if let url = postUrl {
            items.append(url)
        }

        return items
    }

    /// Build the share text
    private static func buildShareText(
        for post: FeedPost,
        appName: String,
        baseUrl: String
    ) -> String {
        var text = ""

        // Add post content if available
        if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Truncate if too long
            let maxLength = 200
            if post.content.count > maxLength {
                text = String(post.content.prefix(maxLength)) + "..."
            } else {
                text = post.content
            }
            text += "\n\n"
        }

        // Add attribution
        text += "Shared from \(appName)"

        return text
    }
}

// MARK: - View Extension for Share Sheet Modifier

extension View {
    /// Present a share sheet with the given items
    /// - Parameters:
    ///   - isPresented: Binding to control presentation
    ///   - items: Items to share
    /// - Returns: Modified view
    func shareSheet(isPresented: Binding<Bool>, items: [Any]) -> some View {
        self.sheet(isPresented: isPresented) {
            ActivityShareSheet(activityItems: items)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showShare = false

    VStack {
        Button("Share") {
            showShare = true
        }
    }
    .sheet(isPresented: $showShare) {
        ActivityShareSheet(
            activityItems: ["Test share content", URL(string: "https://nova.social")!],
            onComplete: { completed in
                print("Share completed: \(completed)")
            }
        )
    }
}
