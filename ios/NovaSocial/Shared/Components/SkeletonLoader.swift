import SwiftUI

// MARK: - Reusable Skeleton Loader Components

/// Base shimmer effect view
/// Optimized: Removed unnecessary GeometryReader - Rectangle fills container by default
struct ShimmerEffect: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.15),
                        Color.gray.opacity(0.25),
                        Color.gray.opacity(0.15)
                    ]),
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

// MARK: - User Row Skeleton

/// Skeleton loader for user row items (following/followers lists)
struct UserRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(ShimmerEffect())
                .clipShape(Circle())

            // Name skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 16)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 80, height: 12)
                    .overlay(ShimmerEffect())
            }

            Spacer()

            // Button skeleton
            RoundedRectangle(cornerRadius: 46)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 85, height: 32)
                .overlay(ShimmerEffect())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Message Row Skeleton

/// Skeleton loader for chat message items
struct MessageRowSkeleton: View {
    let isFromMe: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isFromMe {
                // Avatar for other user
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(ShimmerEffect())
                    .clipShape(Circle())
            } else {
                Spacer()
            }

            // Message bubble skeleton
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: CGFloat.random(in: 150...260), height: 44)
                    .overlay(ShimmerEffect())
            }

            if isFromMe {
                // Avatar for me
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(ShimmerEffect())
                    .clipShape(Circle())
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Generic List Skeleton

/// Generic skeleton loader showing multiple placeholder items
struct SkeletonListLoader<Content: View>: View {
    var itemCount: Int = 5
    @ViewBuilder var itemBuilder: () -> Content

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<itemCount, id: \.self) { _ in
                itemBuilder()
            }
        }
    }
}

// MARK: - Feed Post Card Skeleton

/// Skeleton loader for feed post cards (matches FeedPostCard layout)
struct FeedPostCardSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            // Header: Avatar + Name + Time
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .overlay(ShimmerEffect())
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 14)
                        .overlay(ShimmerEffect())

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 60, height: 10)
                        .overlay(ShimmerEffect())
                }

                Spacer()

                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(ShimmerEffect())
                    .clipShape(Circle())
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            // Media placeholder (fixed height to prevent layout shift)
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 375)
                .overlay(ShimmerEffect())

            // Action buttons row
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 20, height: 20)
                        .overlay(ShimmerEffect())
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 10)

            // Caption placeholder
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 14)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 200, height: 14)
                    .overlay(ShimmerEffect())
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color.white)
    }
}

// MARK: - Conversation Row Skeleton

/// Skeleton loader for conversation/message list items (80pt height)
struct ConversationRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
                .overlay(ShimmerEffect())
                .clipShape(Circle())

            // Name + Message
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 16)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 180, height: 14)
                    .overlay(ShimmerEffect())
            }

            Spacer()

            // Time + Badge
            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 50, height: 12)
                    .overlay(ShimmerEffect())

                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .overlay(ShimmerEffect())
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 80)
    }
}

// MARK: - Profile Header Skeleton

/// Skeleton loader for profile header (avatar, stats, bio)
struct ProfileHeaderSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 109, height: 109)
                .overlay(ShimmerEffect())
                .clipShape(Circle())

            // Name
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 140, height: 20)
                .overlay(ShimmerEffect())

            // Username
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 100, height: 14)
                .overlay(ShimmerEffect())

            // Stats row (Posts, Following, Followers)
            HStack(spacing: 40) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 40, height: 20)
                            .overlay(ShimmerEffect())

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 60, height: 12)
                            .overlay(ShimmerEffect())
                    }
                }
            }

            // Bio placeholder
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 14)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 200, height: 14)
                    .overlay(ShimmerEffect())
            }
            .padding(.horizontal, 20)

            // Action buttons
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 36)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(ShimmerEffect())
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Profile Posts Grid Skeleton

/// Skeleton loader for profile posts grid (3 columns)
struct ProfilePostsGridSkeleton: View {
    let itemCount: Int

    init(itemCount: Int = 9) {
        self.itemCount = itemCount
    }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ], spacing: 2) {
            ForEach(0..<itemCount, id: \.self) { _ in
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .aspectRatio(1, contentMode: .fill)
                    .overlay(ShimmerEffect())
            }
        }
    }
}

// MARK: - Comment Skeleton

/// Skeleton loader for comment items
struct CommentSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(ShimmerEffect())
                .clipShape(Circle())

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Username + Time
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 14)
                        .overlay(ShimmerEffect())

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 40, height: 10)
                        .overlay(ShimmerEffect())
                }

                // Comment text
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 14)
                        .overlay(ShimmerEffect())

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 160, height: 14)
                        .overlay(ShimmerEffect())
                }
            }

            Spacer()

            // Like button
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 16, height: 16)
                .overlay(ShimmerEffect())
                .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Notification Row Skeleton

/// Skeleton loader for notification items
struct NotificationRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(ShimmerEffect())
                .clipShape(Circle())

            // Content
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 14)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 80, height: 12)
                    .overlay(ShimmerEffect())
            }

            Spacer()

            // Thumbnail or action
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(ShimmerEffect())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Search Result Skeleton

/// Skeleton loader for search result items
struct SearchResultSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(ShimmerEffect())
                .clipShape(Circle())

            // Name + Username
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 16)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 80, height: 12)
                    .overlay(ShimmerEffect())
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Post Detail Skeleton

/// Full skeleton for PostDetailView (image + comments)
struct PostDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Post header
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(ShimmerEffect())
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 14)
                            .overlay(ShimmerEffect())

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 60, height: 10)
                            .overlay(ShimmerEffect())
                    }

                    Spacer()
                }
                .padding()

                // Image placeholder (square aspect ratio)
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(ShimmerEffect())

                // Action buttons
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay(ShimmerEffect())
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding()

                // Caption
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 14)
                        .overlay(ShimmerEffect())

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 200, height: 14)
                        .overlay(ShimmerEffect())
                }
                .padding(.horizontal)

                Divider()
                    .padding(.vertical)

                // Comments skeleton
                ForEach(0..<3, id: \.self) { _ in
                    CommentSkeleton()
                }
            }
        }
    }
}

// MARK: - Chat Messages Skeleton

/// Skeleton for ChatView messages list
struct ChatMessagesSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { index in
                MessageRowSkeleton(isFromMe: index % 2 == 0)
            }
        }
        .padding(.vertical)
    }
}
