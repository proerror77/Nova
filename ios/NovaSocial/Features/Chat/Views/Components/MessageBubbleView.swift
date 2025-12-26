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
        HStack(alignment: .bottom, spacing: 10) {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                messageContent
                    .contextMenu { contextMenuItems }
                // 時間和狀態
                HStack(spacing: 4) {
                    Text(formattedTime)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.textMuted)
                    statusIcon
                }
            }
            AvatarView(image: nil, url: myAvatarUrl, size: 40)
        }.padding(.horizontal, 16)
    }

    private var otherMessageView: some View {
        HStack(alignment: .bottom, spacing: 10) {
            AvatarView(image: nil, url: senderAvatarUrl, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                otherMessageContent
                    .contextMenu { contextMenuItems }
                // 時間
                Text(formattedTime)
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.textMuted)
            }
            Spacer()
        }.padding(.horizontal, 16)
    }

    // MARK: - 狀態圖標
    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10))
                .foregroundColor(DesignTokens.textMuted)
        case .delivered:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
                .foregroundColor(DesignTokens.textMuted)
        case .read:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
        case .failed:
            Button {
                onRetry?(message)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text("Retry")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 長按菜單
    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("複製", systemImage: "doc.on.doc")
        }

        if message.isFromMe {
            Button(role: .destructive) {
                onLongPress?(message)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }

    // MARK: - 統一消息內容渲染（消除重複代碼）
    @ViewBuilder
    private func renderMessageContent(isFromMe: Bool) -> some View {
        let bubbleColor = isFromMe ? myBubbleColor : otherBubbleColor
        let textColor = isFromMe ? Color.white : otherTextColor
        let alignment: Alignment = isFromMe ? .trailing : .leading

        // 1. 本地圖片
        if let image = message.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .cornerRadius(14)
        }
        // 2. 遠程圖片 URL
        else if message.messageType == .image, let urlString = message.mediaUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 150, height: 150)
                        ProgressView()
                    }
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(14)
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 150, height: 100)
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                            Text("載入失敗")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                @unknown default:
                    EmptyView()
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
                        .font(.system(size: 12))
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
            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 16))
                .lineSpacing(4)
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                .background(bubbleColor)
                .cornerRadius(14)
                .frame(maxWidth: 260, alignment: alignment)
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
                .font(.system(size: 24))
                .foregroundColor(isFromMe ? .white : myBubbleColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.text.isEmpty ? "文件" : message.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isFromMe ? .white : otherTextColor)
                    .lineLimit(1)
                Text("點擊下載")
                    .font(.system(size: 11))
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
                .font(.system(size: 44))
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
