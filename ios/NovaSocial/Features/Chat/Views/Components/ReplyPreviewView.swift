import SwiftUI

// MARK: - Reply Preview View

/// 回覆預覽視圖 - 顯示被引用消息的摘要
struct ReplyPreviewView: View {
    let preview: ReplyPreview
    var isInBubble: Bool = false
    var onTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // 左側指示條
            RoundedRectangle(cornerRadius: 2)
                .fill(DesignTokens.accentColor)
                .frame(width: 3)

            // 內容
            VStack(alignment: .leading, spacing: 2) {
                // 發送者名稱
                Text(preview.senderName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignTokens.accentColor)
                    .lineLimit(1)

                // 消息內容預覽
                HStack(spacing: 4) {
                    // 消息類型圖標
                    if let icon = iconForMessageType(preview.messageType) {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.textSecondary)
                    }

                    Text(preview.content)
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 關閉按鈕（僅在輸入框上方的預覽中顯示）
            if let onDismiss = onDismiss, !isInBubble {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(DesignTokens.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isInBubble ? Color.clear : DesignTokens.surface)
        .cornerRadius(isInBubble ? 0 : 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - Helpers

    private func iconForMessageType(_ type: ChatMessageType) -> String? {
        switch type {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .audio:
            return "waveform"
        case .location:
            return "location"
        case .file:
            return "doc"
        default:
            return nil
        }
    }
}

// MARK: - Reply Input Preview

/// 輸入框上方的回覆預覽
struct ReplyInputPreview: View {
    let preview: ReplyPreview
    let onDismiss: () -> Void

    var body: some View {
        ReplyPreviewView(
            preview: preview,
            isInBubble: false,
            onDismiss: onDismiss
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Reply Bubble Preview

/// 消息氣泡內的回覆預覽（較小的樣式）
struct ReplyBubblePreview: View {
    let preview: ReplyPreview
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // 左側指示條
            RoundedRectangle(cornerRadius: 1.5)
                .fill(DesignTokens.accentColor.opacity(0.8))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(preview.senderName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignTokens.accentColor)
                    .lineLimit(1)

                Text(preview.content)
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.05))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Previews

#Preview("Reply Preview - Input") {
    VStack {
        ReplyPreviewView(
            preview: ReplyPreview(
                messageId: "1",
                senderName: "John",
                content: "這是一條測試消息，內容比較長可能會被截斷",
                messageType: .text
            ),
            onDismiss: {}
        )

        ReplyPreviewView(
            preview: ReplyPreview(
                messageId: "2",
                senderName: "Alice",
                content: "[圖片]",
                messageType: .image
            ),
            onDismiss: {}
        )
    }
    .padding()
}

#Preview("Reply Bubble Preview") {
    ReplyBubblePreview(
        preview: ReplyPreview(
            messageId: "1",
            senderName: "John",
            content: "原始消息內容",
            messageType: .text
        ),
        onTap: {}
    )
    .padding()
}
