import SwiftUI

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
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.accentColor)

                    // 時長
                    Text(formatDuration(duration))
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 播放預覽按鈕
                    Button(action: {}) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(DesignTokens.accentColor)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
            .background(DesignTokens.surface)
            .cornerRadius(12)
            .padding(.horizontal, 16)

            // 轉文字結果預覽
            if showTextPreview {
                textPreviewSection
            }

            Spacer().frame(height: 24)

            // 操作按鈕
            VStack(spacing: 12) {
                // 發送語音
                OptionButton(
                    icon: "mic.fill",
                    title: "發送語音",
                    subtitle: formatDuration(duration),
                    color: DesignTokens.accentColor,
                    action: {
                        onSendVoice()
                        isPresented = false
                    }
                )

                // 轉換成文字
                OptionButton(
                    icon: "text.bubble.fill",
                    title: isConverting ? "正在轉換..." : (recognizedText.isEmpty ? "轉換成文字" : "發送文字"),
                    subtitle: isConverting ? nil : (recognizedText.isEmpty ? "使用語音識別" : recognizedText),
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
                    Text("取消")
                        .font(.system(size: 16, weight: .medium))
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
                Text("識別結果")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.textSecondary)

                Spacer()

                if !recognizedText.isEmpty {
                    Button("編輯") {
                        // TODO: 允許編輯文字
                    }
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.accentColor)
                }
            }

            if isConverting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在識別語音...")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                }
                .padding(.vertical, 8)
            } else if recognizedText.isEmpty {
                Text("無法識別語音內容")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
            } else {
                Text(recognizedText)
                    .font(.system(size: 15))
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
                            .font(.system(size: 18))
                            .foregroundColor(color)
                    }
                }

                // 文字
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
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
