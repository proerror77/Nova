import SwiftUI

/// View for displaying voice messages in chat with waveform visualization
struct VoiceMessageView: View {
    let message: ChatMessage
    let isFromMe: Bool
    var audioPlayer: AudioPlayerService  // @Observable 不需要 @ObservedObject
    @State private var isPlaying = false

    // 預設波形高度 (基於消息 ID 生成確定性波形)
    private var waveformHeights: [CGFloat] {
        let seed = message.id.hashValue
        var heights: [CGFloat] = []
        for i in 0..<16 {
            // 使用 sin 函數生成平滑波形
            let value = abs(sin(Double(seed + i * 7) * 0.5)) * 0.7 + 0.3
            heights.append(CGFloat(value) * 18 + 6)
        }
        return heights
    }

    private var duration: TimeInterval { message.audioDuration ?? 0 }
    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.playingMessageId == message.id && audioPlayer.isPlaying
    }

    private var playbackProgress: Double {
        guard audioPlayer.playingMessageId == message.id, duration > 0 else { return 0 }
        return min(audioPlayer.currentTime / duration, 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            // 播放/暫停按鈕
            Button(action: { togglePlayback() }) {
                Circle()
                    .fill(isFromMe ? Color.white.opacity(0.3) : Color(red: 0.91, green: 0.18, blue: 0.30))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(.white)
                    )
            }

            // 波形可視化（帶進度指示）
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(0..<16, id: \.self) { index in
                        let barProgress = Double(index) / 16.0
                        let isPlayed = playbackProgress > barProgress

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(barColor(isPlayed: isPlayed))
                            .frame(width: 3, height: waveformHeights[index])
                    }
                }
                .frame(height: 24, alignment: .center)
            }
            .frame(width: 80, height: 24)

            // 時間顯示
            Text(isCurrentlyPlaying ? formatCurrentTime() : formattedDuration)
                .font(Font.custom("Helvetica Neue", size: 12).monospacedDigit())
                .foregroundColor(isFromMe ? Color.white.opacity(0.8) : DesignTokens.textMuted)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 14))
        .background(isFromMe ? Color(red: 0.91, green: 0.18, blue: 0.30) : DesignTokens.chatBubbleOther)
        .cornerRadius(20)
        .animation(.easeInOut(duration: 0.1), value: playbackProgress)
    }

    // 根據播放進度決定波形條顏色
    private func barColor(isPlayed: Bool) -> Color {
        if isFromMe {
            return isPlayed ? Color.white : Color.white.opacity(0.4)
        } else {
            return isPlayed ? Color(red: 0.91, green: 0.18, blue: 0.30) : DesignTokens.textMuted.opacity(0.5)
        }
    }

    private func formatCurrentTime() -> String {
        let time = audioPlayer.currentTime
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }

    private func togglePlayback() {
        if isCurrentlyPlaying {
            audioPlayer.pause()
        } else if audioPlayer.playingMessageId == message.id {
            audioPlayer.resume()
        } else if let url = message.audioUrl {
            audioPlayer.play(url: url, messageId: message.id)
        } else if let data = message.audioData {
            audioPlayer.play(data: data, messageId: message.id)
        } else if let urlString = message.mediaUrl, let url = URL(string: urlString) {
            // 支援遠程語音消息 URL
            audioPlayer.play(url: url, messageId: message.id)
        }
    }
}
