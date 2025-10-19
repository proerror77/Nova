//
//  ExamplePostCard.swift
//  Nova Design System Example
//
//  Demonstrates theme usage with a PostCard component
//  Copyright © 2025 Nova. All rights reserved.
//

import SwiftUI

// MARK: - Post Card Example

struct PostCard: View {
    @Environment(\.theme) private var theme

    let author: String
    let content: String
    let timestamp: String
    let imageName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            // Header
            HStack(spacing: theme.space.sm) {
                Circle()
                    .fill(theme.colors.brandPrimary)
                    .frame(
                        width: theme.metric.avatarMD,
                        height: theme.metric.avatarMD
                    )
                    .overlay(
                        Text(String(author.prefix(1)))
                            .font(theme.type.labelSM)
                            .foregroundColor(theme.colors.brandOn)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(author)
                        .font(theme.type.labelSM)
                        .foregroundColor(theme.colors.fgPrimary)

                    Text(timestamp)
                        .font(theme.type.labelSM)
                        .foregroundColor(theme.colors.fgSecondary)
                }

                Spacer()
            }

            // Content
            Text(content)
                .font(theme.type.bodyMD)
                .foregroundColor(theme.colors.fgPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Image (if present)
            if let imageName = imageName {
                Rectangle()
                    .fill(theme.colors.bgElevated)
                    .aspectRatio(1, contentMode: .fill)
                    .cornerRadius(theme.metric.postCardCorner)
                    .overlay(
                        Image(systemName: imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(theme.colors.fgSecondary)
                    )
            }

            // Actions
            HStack(spacing: theme.space.xl) {
                ActionButton(
                    icon: "heart",
                    label: "Like",
                    theme: theme
                )

                ActionButton(
                    icon: "bubble.left",
                    label: "Comment",
                    theme: theme
                )

                ActionButton(
                    icon: "arrow.turn.up.right",
                    label: "Share",
                    theme: theme
                )
            }
        }
        .padding(.horizontal, theme.metric.postCardPaddingX)
        .padding(.vertical, theme.metric.postCardPaddingY)
        .background(theme.colors.bgSurface)
        .cornerRadius(theme.metric.postCardCorner)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metric.postCardCorner)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let label: String
    let theme: Theme

    var body: some View {
        Button(action: {}) {
            HStack(spacing: theme.space.xs) {
                Image(systemName: icon)
                    .font(.system(size: theme.metric.iconMD))

                Text(label)
                    .font(theme.type.labelSM)
            }
            .foregroundColor(theme.colors.fgSecondary)
        }
        .frame(minWidth: theme.metric.hitAreaMin, minHeight: theme.metric.hitAreaMin)
    }
}

// MARK: - Preview

#if DEBUG
struct PostCard_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Brand A Light
            PostCard(
                author: "Jane Cooper",
                content: "Just shipped a new feature! The design system makes everything so much easier to build. 🚀",
                timestamp: "2h ago",
                imageName: "photo"
            )
            .theme(.brandALight)
            .previewDisplayName("Brand A Light")
            .padding()

            // Brand A Dark
            PostCard(
                author: "Jane Cooper",
                content: "Just shipped a new feature! The design system makes everything so much easier to build. 🚀",
                timestamp: "2h ago",
                imageName: "photo"
            )
            .theme(.brandADark)
            .previewDisplayName("Brand A Dark")
            .padding()
            .background(Color.black)

            // Brand B Light
            PostCard(
                author: "John Doe",
                content: "The new theme system is amazing! Love how easy it is to switch between brands.",
                timestamp: "5h ago",
                imageName: nil
            )
            .theme(.brandBLight)
            .previewDisplayName("Brand B Light")
            .padding()

            // Brand B Dark
            PostCard(
                author: "John Doe",
                content: "The new theme system is amazing! Love how easy it is to switch between brands.",
                timestamp: "5h ago",
                imageName: nil
            )
            .theme(.brandBDark)
            .previewDisplayName("Brand B Dark")
            .padding()
            .background(Color.black)
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
