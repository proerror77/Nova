import SwiftUI
import MapKit
import CoreLocation

/// Chat message bubble view with support for text, images, voice, location, and files
struct MessageBubbleView: View {
    let message: ChatMessage
    var audioPlayer: AudioPlayerService? = nil
    var senderAvatarUrl: String? = nil  // 發送者頭像URL
    var myAvatarUrl: String? = nil  // 當前用戶頭像URL
    var onLongPress: ((ChatMessage) -> Void)? = nil  // 長按回調
    var onRetry: ((ChatMessage) -> Void)? = nil  // 重試回調（發送失敗時）
    var onReply: ((ChatMessage) -> Void)? = nil  // 回覆回調
    var onTapReply: ((String) -> Void)? = nil  // 點擊回覆預覽時跳轉到原消息
    var onEdit: ((ChatMessage) -> Void)? = nil  // 編輯回調（僅限自己的文字消息）
    var onReaction: ((ChatMessage, String) -> Void)? = nil  // Emoji 反應回調
    var onRecall: ((ChatMessage) -> Void)? = nil  // 撤回回調（2分鐘內可撤回）
    var currentUserId: String = ""  // 當前用戶 ID（用於反應顯示）

    private let myBubbleColor = Color(red: 0.91, green: 0.20, blue: 0.34)
    private let otherBubbleColor = Color(red: 0.92, green: 0.92, blue: 0.92)
    private let otherTextColor = Color(red: 0.34, green: 0.34, blue: 0.34)

    // 時間格式化器
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var formattedTime: String {
        Self.timeFormatter.string(from: message.timestamp)
    }

    var body: some View {
        if message.isFromMe { myMessageView } else { otherMessageView }
    }

    private var myMessageView: some View {
        HStack(alignment: .top, spacing: 10.w) {
            Spacer()
            VStack(alignment: .trailing, spacing: 4.h) {
                messageContent
                    .contextMenu { contextMenuItems }
                // 反應顯示
                if !message.reactions.isEmpty {
                    MessageReactionsView(
                        reactions: message.reactions,
                        currentUserId: currentUserId,
                        onTap: { emoji in
                            onReaction?(message, emoji)
                        }
                    )
                }
                // 時間和狀態
                HStack(spacing: 4.w) {
                    if message.isEdited {
                        Text("Edited")
                            .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                            .foregroundColor(DesignTokens.textMuted)
                    }
                    Text(formattedTime)
                        .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                        .foregroundColor(DesignTokens.textMuted)
                    statusIcon
                }
            }
            AvatarView(image: nil, url: myAvatarUrl, size: 40.s)
        }
        .padding(.trailing, 16)
    }

    private var otherMessageView: some View {
        HStack(alignment: .top, spacing: 10.w) {
            AvatarView(image: nil, url: senderAvatarUrl, size: 40.s)
            VStack(alignment: .leading, spacing: 4.h) {
                otherMessageContent
                    .contextMenu { contextMenuItems }
                // 反應顯示
                if !message.reactions.isEmpty {
                    MessageReactionsView(
                        reactions: message.reactions,
                        currentUserId: currentUserId,
                        onTap: { emoji in
                            onReaction?(message, emoji)
                        }
                    )
                }
                // 時間
                HStack(spacing: 4.w) {
                    Text(formattedTime)
                        .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                        .foregroundColor(DesignTokens.textMuted)
                    if message.isEdited {
                        Text("Edited")
                            .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                            .foregroundColor(DesignTokens.textMuted)
                    }
                }
            }
            Spacer()
        }
        .padding(.leading, 16)
    }

    // MARK: - 狀態圖標
    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .sending:
            HStack(spacing: 2) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Sending")
                    .font(Font.custom("SFProDisplay-Regular", size: 9.f))
                    .foregroundColor(DesignTokens.textMuted)
            }
        case .sent:
            HStack(spacing: 2) {
                Image(systemName: "checkmark")
                    .font(Font.custom("SFProDisplay-Regular", size: 9.f))
                    .foregroundColor(DesignTokens.textMuted)
                Text("Sent")
                    .font(Font.custom("SFProDisplay-Regular", size: 9.f))
                    .foregroundColor(DesignTokens.textMuted)
            }
        case .delivered:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle")
                    .font(Font.custom("SFProDisplay-Regular", size: 9.f))
                    .foregroundColor(DesignTokens.textMuted)
                Text("Delivered")
                    .font(Font.custom("SFProDisplay-Regular", size: 9.f))
                    .foregroundColor(DesignTokens.textMuted)
            }
        case .read:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 9.f))
                    .foregroundColor(.blue)
                Text("Read")
                    .font(Font.custom("SFProDisplay-Medium", size: 9.f))
                    .foregroundColor(.blue)
            }
        case .failed:
            Button {
                onRetry?(message)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(.red)
                    Text("Retry")
                        .font(Font.custom("SFProDisplay-Medium", size: 10.f))
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 長按菜單
    @ViewBuilder
    private var contextMenuItems: some View {
        // 快速反應
        Menu {
            ForEach(["👍", "❤️", "😂", "😮", "😢", "🎉"], id: \.self) { emoji in
                Button {
                    onReaction?(message, emoji)
                } label: {
                    Text(emoji)
                }
            }
        } label: {
            Label("React", systemImage: "face.smiling")
        }

        // 回覆
        Button {
            onReply?(message)
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        // 複製
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if message.isFromMe {
            // 編輯（僅限文字消息）
            if message.messageType == .text && !message.isRecalled {
                Button {
                    onEdit?(message)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            // 撤回（2分鐘內可撤回）
            if message.canRecall {
                Button {
                    onRecall?(message)
                } label: {
                    Label("Unsend", systemImage: "arrow.uturn.backward")
                }
            }

            Button(role: .destructive) {
                onLongPress?(message)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - 回覆預覽（氣泡內）
    @ViewBuilder
    private func replyPreviewInBubble(isFromMe: Bool) -> some View {
        if let reply = message.replyToMessage {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isFromMe ? Color.white.opacity(0.6) : DesignTokens.accentColor.opacity(0.8))
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(reply.senderName)
                        .font(Font.custom("SFProDisplay-Medium", size: 11.f))
                        .foregroundColor(isFromMe ? Color.white.opacity(0.9) : DesignTokens.accentColor)
                        .lineLimit(1)

                    Text(reply.content)
                        .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                        .foregroundColor(isFromMe ? Color.white.opacity(0.7) : DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isFromMe ? Color.white.opacity(0.15) : Color.black.opacity(0.05))
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture {
                onTapReply?(reply.messageId)
            }
        }
    }

    // MARK: - 統一消息內容渲染（消除重複代碼）
    @ViewBuilder
    private func renderMessageContent(isFromMe: Bool) -> some View {
        let bubbleColor = isFromMe ? myBubbleColor : otherBubbleColor
        let textColor = isFromMe ? Color.white : otherTextColor
        let alignment: Alignment = isFromMe ? .trailing : .leading

        // 0. 已撤回消息
        if message.isRecalled {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(DesignTokens.textMuted)
                Text(isFromMe ? "You unsent a message" : "This message was unsent")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(DesignTokens.textMuted)
                    .italic()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        // 1. 本地圖片
        else if let image = message.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .cornerRadius(14)
        }
        // 2. 遠程圖片 URL - 使用 CachedAsyncImage 優化緩存
        else if message.messageType == .image, let urlString = message.mediaUrl, let url = URL(string: urlString) {
            CachedAsyncImage(
                url: url,
                targetSize: CGSize(width: 400, height: 400),  // 聊天氣泡適當大小
                enableProgressiveLoading: true,
                priority: .normal
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .cornerRadius(14)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 150, height: 150)
                    ProgressView()
                }
            }
        }
        // 3. 位置消息
        else if let location = message.location {
            LocationMessageView(location: location)
        }
        // 4. 語音消息
        else if message.messageType == .audio || message.audioData != nil || message.audioUrl != nil {
            if let player = audioPlayer {
                VoiceMessageView(message: message, isFromMe: isFromMe, audioPlayer: player)
            } else {
                // 無播放器時顯示佔位符
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(textColor)
                    Text(formatDuration(message.audioDuration ?? 0))
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(textColor.opacity(0.8))
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 16))
                .background(bubbleColor)
                .cornerRadius(20)
            }
        }
        // 5. 文件消息
        else if message.messageType == .file {
            fileMessageView(isFromMe: isFromMe)
        }
        // 6. 視頻消息
        else if message.messageType == .video, let urlString = message.mediaUrl {
            videoThumbnailView(urlString: urlString, isFromMe: isFromMe)
        }
        // 7. 文字消息
        else {
            HStack {
                if isFromMe { Spacer(minLength: 0) }
                
                VStack(alignment: .leading, spacing: 8.h) {
                    // 回覆預覽
                    replyPreviewInBubble(isFromMe: isFromMe)

                    // 消息內容
                    Text(message.text)
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.leading)
                }
                .padding(EdgeInsets(top: 12.h, leading: 16.w, bottom: 12.h, trailing: 16.w))
                .background(bubbleColor)
                .cornerRadius(14.s)
                .frame(maxWidth: 237.w, alignment: alignment)
                
                if !isFromMe { Spacer(minLength: 0) }
            }
        }
    }

    // MARK: - 向後兼容的包裝屬性
    @ViewBuilder private var messageContent: some View {
        renderMessageContent(isFromMe: true)
    }

    @ViewBuilder private var otherMessageContent: some View {
        renderMessageContent(isFromMe: false)
    }

    // MARK: - 文件消息視圖
    private func fileMessageView(isFromMe: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                .foregroundColor(isFromMe ? .white : myBubbleColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.text.isEmpty ? "File" : message.text)
                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                    .foregroundColor(isFromMe ? .white : otherTextColor)
                    .lineLimit(1)
                Text("Tap to download")
                    .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                    .foregroundColor(isFromMe ? .white.opacity(0.7) : DesignTokens.textMuted)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .background(isFromMe ? myBubbleColor : otherBubbleColor)
        .cornerRadius(14)
    }

    // MARK: - 視頻縮略圖視圖
    private func videoThumbnailView(urlString: String, isFromMe: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.8))
                .frame(width: 200, height: 150)

            Image(systemName: "play.circle.fill")
                .font(Font.custom("SFProDisplay-Regular", size: 44.f))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    // MARK: - 格式化時長
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
