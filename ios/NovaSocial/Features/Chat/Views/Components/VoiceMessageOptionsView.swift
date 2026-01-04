import SwiftUI
import AVFoundation

// MARK: - Voice Message Options View

/// 語音訊息選項面板 - 仿微信風格
/// 錄音完成後顯示：發送語音、轉文字、取消
struct VoiceMessageOptionsView: View {
    // MARK: - Properties

    @Binding var isPresented: Bool

    /// 錄音時長
    let duration: TimeInterval

    /// 音頻文件 URL
    let audioURL: URL

    /// 音頻數據
    let audioData: Data

    /// 識別出的文字（如果已轉換）
    @Binding var recognizedText: String

    /// 是否正在轉換文字
    @Binding var isConverting: Bool

    // MARK: - Callbacks

    /// 發送語音訊息
    let onSendVoice: () -> Void

    /// 發送文字訊息
    let onSendText: (String) -> Void

    /// 取消
    let onCancel: () -> Void

    /// 開始轉換文字
    let onConvertToText: () -> Void

    // MARK: - State

    @State private var showTextPreview = false
    @State private var isPlaying = false
    @State private var isEditingText = false
    @State private var editableText = ""
    @StateObject private var audioPlayer = VoicePreviewPlayer()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 拖動指示條
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // 錄音信息
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // 波形圖標
                    Image(systemName: "waveform")
                        .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                        .foregroundColor(DesignTokens.accentColor)

                    // 時長
                    Text(formatDuration(duration))
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 播放預覽按鈕
                    Button(action: {
                        togglePlayback()
                    }) {
                        Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(Font.custom("SFProDisplay-Regular", size: 32.f))
                            .foregroundColor(DesignTokens.accentColor)
                    }
                }
                .padding(.horizontal, 20)

                // 播放進度條
                if audioPlayer.isPlaying || audioPlayer.currentTime > 0 {
                    ProgressView(value: audioPlayer.currentTime, total: duration)
                        .progressViewStyle(LinearProgressViewStyle(tint: DesignTokens.accentColor))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 16)
            .background(DesignTokens.surface)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .onDisappear {
                audioPlayer.stop()
            }

            // 轉文字結果預覽
            if showTextPreview {
                textPreviewSection
            }

            Spacer().frame(height: 24)

            // 操作按鈕
            VStack(spacing: 12) {
                // Send voice
                OptionButton(
                    icon: "mic.fill",
                    title: "Send Voice",
                    subtitle: formatDuration(duration),
                    color: DesignTokens.accentColor,
                    action: {
                        onSendVoice()
                        isPresented = false
                    }
                )

                // Convert to text
                OptionButton(
                    icon: "text.bubble.fill",
                    title: isConverting ? "Converting..." : (recognizedText.isEmpty ? "Convert to Text" : "Send Text"),
                    subtitle: isConverting ? nil : (recognizedText.isEmpty ? "Use speech recognition" : recognizedText),
                    color: .blue,
                    isLoading: isConverting,
                    action: {
                        if recognizedText.isEmpty && !isConverting {
                            onConvertToText()
                            showTextPreview = true
                        } else if !recognizedText.isEmpty {
                            onSendText(recognizedText)
                            isPresented = false
                        }
                    }
                )
                .disabled(isConverting)

                // 取消
                Button(action: {
                    onCancel()
                    isPresented = false
                }) {
                    Text("Cancel")
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(DesignTokens.backgroundColor)
        .onChange(of: recognizedText) { _, newValue in
            if !newValue.isEmpty {
                showTextPreview = true
            }
        }
    }

    // MARK: - Text Preview Section

    private var textPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isEditingText ? "Edit Text" : "Recognition Result")
                    .font(Font.custom("SFProDisplay-Medium", size: 13.f))
                    .foregroundColor(DesignTokens.textSecondary)

                Spacer()

                if !recognizedText.isEmpty && !isConverting {
                    Button(isEditingText ? "Done" : "Edit") {
                        if isEditingText {
                            // 完成編輯，保存文字
                            recognizedText = editableText
                            isEditingText = false
                        } else {
                            // 開始編輯
                            editableText = recognizedText
                            isEditingText = true
                        }
                    }
                    .font(Font.custom("SFProDisplay-Medium", size: 13.f))
                    .foregroundColor(DesignTokens.accentColor)
                }
            }

            if isConverting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Recognizing speech...")
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(DesignTokens.textSecondary)
                }
                .padding(.vertical, 8)
            } else if recognizedText.isEmpty && !isEditingText {
                Text("Unable to recognize speech")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
            } else if isEditingText {
                // 編輯模式
                TextEditor(text: $editableText)
                    .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                    .foregroundColor(DesignTokens.textPrimary)
                    .frame(minHeight: 60, maxHeight: 120)
                    .padding(8)
                    .background(DesignTokens.backgroundColor)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DesignTokens.accentColor, lineWidth: 1)
                    )
            } else {
                Text(recognizedText)
                    .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                    .foregroundColor(DesignTokens.textPrimary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(DesignTokens.surface)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func togglePlayback() {
        if audioPlayer.isPlaying {
            audioPlayer.stop()
        } else {
            audioPlayer.play(url: audioURL)
        }
    }
}

// MARK: - Voice Preview Player

/// 語音預覽播放器
final class VoicePreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(url: URL) {
        do {
            // 配置音頻會話
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            // 創建播放器
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()

            isPlaying = true
            currentTime = 0

            // 啟動進度更新計時器
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateProgress()
            }

            #if DEBUG
            print("[VoicePreviewPlayer] 開始播放: \(url.lastPathComponent)")
            #endif
        } catch {
            #if DEBUG
            print("[VoicePreviewPlayer] 播放失敗: \(error)")
            #endif
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        currentTime = 0
    }

    private func updateProgress() {
        guard let player = player else { return }
        currentTime = player.currentTime
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stop()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.stop()
        }
        #if DEBUG
        if let error = error {
            print("[VoicePreviewPlayer] 解碼錯誤: \(error)")
        }
        #endif
    }
}

// MARK: - Option Button

private struct OptionButton: View {
    let icon: String
    let title: String
    let subtitle: String?
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 圖標
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                            .foregroundColor(color)
                    }
                }

                // 文字
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(DesignTokens.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                            .foregroundColor(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignTokens.surface)
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#Preview {
    VoiceMessageOptionsView(
        isPresented: .constant(true),
        duration: 5.5,
        audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
        audioData: Data(),
        recognizedText: .constant(""),
        isConverting: .constant(false),
        onSendVoice: {},
        onSendText: { _ in },
        onCancel: {},
        onConvertToText: {}
    )
}
