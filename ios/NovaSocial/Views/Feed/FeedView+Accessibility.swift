//
//  FeedView+Accessibility.swift
//  NovaSocial
//
//  Created by Nova Team
//  Accessibility extensions for Feed views
//

import SwiftUI

// MARK: - Feed Post Card Accessibility

extension View {

    /// Add comprehensive accessibility support to a feed post card
    func feedPostAccessibility(
        author: String,
        content: String,
        timestamp: Date,
        likes: Int,
        comments: Int,
        isLiked: Bool,
        onLike: @escaping () -> Void,
        onComment: @escaping () -> Void,
        onShare: @escaping () -> Void
    ) -> some View {
        self
            // Group all post content for coherent VoiceOver reading
            .accessibilityElement(children: .contain)
            .accessibilityLabel(feedPostLabel(
                author: author,
                content: content,
                timestamp: timestamp,
                likes: likes,
                comments: comments,
                isLiked: isLiked
            ))
            // Custom actions for quick interaction
            .accessibilityActions {
                AccessibilityAction(name: isLiked ? "Unlike" : "Like") {
                    onLike()
                }
                AccessibilityAction(name: "Comment") {
                    onComment()
                }
                AccessibilityAction(name: "Share") {
                    onShare()
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Feed.postCell)
    }

    /// Generate comprehensive VoiceOver label for a post
    private func feedPostLabel(
        author: String,
        content: String,
        timestamp: Date,
        likes: Int,
        comments: Int,
        isLiked: Bool
    ) -> String {
        var parts: [String] = []

        // Author
        parts.append("\(author)")

        // Content
        parts.append(content)

        // Timestamp
        let timeAgo = timestamp.timeAgoDisplay()
        parts.append("\(timeAgo)")

        // Engagement
        if likes > 0 {
            parts.append("\(likes) \(likes == 1 ? "like" : "likes")")
        }
        if comments > 0 {
            parts.append("\(comments) \(comments == 1 ? "comment" : "comments")")
        }

        // Like status
        if isLiked {
            parts.append("You liked this post")
        }

        return parts.joined(separator: ". ")
    }
}

// MARK: - Feed Action Buttons

struct FeedActionButton: View {

    let icon: String
    let activeIcon: String?
    let count: Int?
    let isActive: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    init(
        icon: String,
        activeIcon: String? = nil,
        count: Int? = nil,
        isActive: Bool = false,
        accessibilityLabel: String,
        accessibilityHint: String = "",
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.activeIcon = activeIcon
        self.count = count
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()

            // Announce action for VoiceOver
            announceAction()
        }) {
            HStack(spacing: 4) {
                Image(systemName: isActive && activeIcon != nil ? activeIcon! : icon)
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? .red : .primary)

                if let count = count, count > 0 {
                    Text("\(count.abbreviated)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .frame(
                minWidth: AccessibilityConstants.minTouchTargetSize,
                minHeight: AccessibilityConstants.minTouchTargetSize
            )
        }
        // Accessibility
        .accessibilityLabel(labelWithCount)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isActive ? "Active" : "")
    }

    private var labelWithCount: String {
        if let count = count, count > 0 {
            return "\(accessibilityLabel), \(count)"
        }
        return accessibilityLabel
    }

    private func announceAction() {
        if isActive {
            AccessibilityHelper.announce("\(accessibilityLabel) activated")
        } else {
            AccessibilityHelper.announce("\(accessibilityLabel) deactivated")
        }
    }
}

// MARK: - Feed Refresh Control

extension View {

    /// Add accessible pull-to-refresh functionality
    func accessibleRefreshable(action: @escaping () async -> Void) -> some View {
        self.refreshable {
            await action()
            AccessibilityHelper.announce("Feed refreshed")
        }
        .accessibilityAction(named: "Refresh") {
            Task {
                await action()
            }
        }
    }
}

// MARK: - Feed Loading State

struct FeedLoadingView: View {

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading posts...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading posts")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Feed Empty State

struct FeedEmptyView: View {

    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("No Posts Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle = actionTitle, let action = action {
                AccessibleButton(
                    actionTitle,
                    icon: "plus.circle.fill",
                    style: .primary,
                    action: action
                )
                .accessibilityHint("Create your first post")
                .padding(.horizontal, 40)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Feed Error State

struct FeedErrorView: View {

    let error: Error
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Something Went Wrong")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AccessibleButton(
                "Try Again",
                icon: "arrow.clockwise",
                style: .primary,
                action: retryAction
            )
            .accessibilityHint("Reload the feed")
            .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Helper Extensions

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension Int {
    var abbreviated: String {
        if self < 1000 {
            return "\(self)"
        } else if self < 10000 {
            return String(format: "%.1fK", Double(self) / 1000.0)
        } else if self < 1_000_000 {
            return "\(self / 1000)K"
        } else {
            return String(format: "%.1fM", Double(self) / 1_000_000.0)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FeedAccessibility_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Action buttons
            HStack(spacing: 32) {
                FeedActionButton(
                    icon: "heart",
                    activeIcon: "heart.fill",
                    count: 42,
                    isActive: false,
                    accessibilityLabel: "Like",
                    accessibilityHint: "Double tap to like this post"
                ) {
                    print("Like tapped")
                }

                FeedActionButton(
                    icon: "bubble.right",
                    count: 8,
                    accessibilityLabel: "Comment",
                    accessibilityHint: "Double tap to open comments"
                ) {
                    print("Comment tapped")
                }

                FeedActionButton(
                    icon: "square.and.arrow.up",
                    accessibilityLabel: "Share",
                    accessibilityHint: "Double tap to share this post"
                ) {
                    print("Share tapped")
                }
            }

            Divider()

            // Empty state
            FeedEmptyView(
                message: "Follow people to see their posts in your feed",
                actionTitle: "Explore",
                action: { print("Explore tapped") }
            )
            .frame(height: 300)

            Divider()

            // Error state
            FeedErrorView(
                error: NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network connection lost"]),
                retryAction: { print("Retry tapped") }
            )
            .frame(height: 300)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
