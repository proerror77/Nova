import SwiftUI

/// Common emoji reactions for quick access
struct ReactionPickerView: View {
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    // 常用的 emoji 反應
    private let quickEmojis = ["👍", "❤️", "😂", "😮", "😢", "🎉"]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(quickEmojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                }
                .buttonStyle(.plain)
            }

            // 更多選項按鈕
            Button {
                onDismiss()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20.f))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(DesignTokens.surface)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
    }
}

/// Display reactions under a message bubble
struct MessageReactionsView: View {
    let reactions: [ReactionSummary]
    let currentUserId: String
    let onTap: (String) -> Void

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 6) {
                ForEach(reactions) { reaction in
                    Button {
                        onTap(reaction.emoji)
                    } label: {
                        HStack(spacing: 3) {
                            Text(reaction.emoji)
                                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            if reaction.count > 1 {
                                Text("\(reaction.count)")
                                    .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                                    .foregroundColor(reaction.hasReacted(userId: currentUserId) ? .white : DesignTokens.textSecondary)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(reaction.hasReacted(userId: currentUserId)
                                      ? DesignTokens.accentColor.opacity(0.9)
                                      : Color.gray.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ReactionPickerView(
            onSelect: { print("Selected: \($0)") },
            onDismiss: { print("Dismissed") }
        )

        MessageReactionsView(
            reactions: [
                ReactionSummary(emoji: "👍", count: 3, userIds: ["user1", "user2", "user3"]),
                ReactionSummary(emoji: "❤️", count: 1, userIds: ["user1"])
            ],
            currentUserId: "user1",
            onTap: { print("Tapped: \($0)") }
        )
    }
    .padding()
}
