import SwiftUI
import AVFoundation

// MARK: - Voice Record Button

/// A press-and-hold button for recording voice messages
/// Press and hold to record, release to send, slide up to cancel
struct VoiceRecordButton: View {
    // MARK: - Properties

    /// Callback when recording is completed with audio data
    let onRecordingComplete: (Data, TimeInterval) -> Void

    /// Optional callback when recording is cancelled
    var onRecordingCancelled: (() -> Void)?

    // MARK: - State

    @State private var audioRecorder = AudioRecorderService()
    @State private var isPressed = false
    @State private var dragOffset: CGSize = .zero
    @State private var showCancelHint = false
    @State private var pulseAnimation = false

    // Cancel threshold - if user drags up more than this, cancel the recording
    private let cancelThreshold: CGFloat = -80

    // Minimum recording duration (seconds)
    private let minimumDuration: TimeInterval = 0.5

    var body: some View {
        ZStack {
            // Background circle with pulse animation
            if audioRecorder.isRecording {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: pulseAnimation ? 70 : 50, height: pulseAnimation ? 70 : 50)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
            }

            // Main button
            Circle()
                .fill(audioRecorder.isRecording ? Color.red : Color.gray.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20.f))
                        .foregroundColor(audioRecorder.isRecording ? .white : .primary)
                }
                .scaleEffect(isPressed ? 1.2 : 1.0)
                .offset(dragOffset)
                .animation(.spring(response: 0.3), value: isPressed)

            // Recording indicator overlay
            if audioRecorder.isRecording {
                VStack(spacing: 8) {
                    // Cancel hint
                    if showCancelHint {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.caption)
                            Text("Release to cancel")
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .offset(y: -80)
                    }

                    Spacer()

                    // Recording info
                    HStack(spacing: 12) {
                        // Audio level indicator
                        AudioLevelView(level: audioRecorder.audioLevel)
                            .frame(width: 30, height: 20)

                        // Duration
                        Text(formatDuration(audioRecorder.recordingDuration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)

                        // Recording dot
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulseAnimation ? 1 : 0.5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .offset(y: -60)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .onAppear {
            audioRecorder.checkPermission()
        }
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(_ value: DragGesture.Value) {
        // Start recording on initial press
        if !isPressed && !audioRecorder.isRecording {
            isPressed = true
            startRecording()
        }

        // Track drag for cancel gesture
        dragOffset = CGSize(width: 0, height: min(0, value.translation.height))
        showCancelHint = value.translation.height < cancelThreshold
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        isPressed = false
        dragOffset = .zero
        showCancelHint = false
        pulseAnimation = false

        // Check if should cancel
        if value.translation.height < cancelThreshold {
            cancelRecording()
        } else {
            stopRecording()
        }
    }

    // MARK: - Recording Control

    private func startRecording() {
        Task {
            let success = await audioRecorder.startRecording()
            if success {
                await MainActor.run {
                    pulseAnimation = true
                }
            } else {
                await MainActor.run {
                    isPressed = false
                }
            }
        }
    }

    private func stopRecording() {
        guard audioRecorder.isRecording else { return }

        if let result = audioRecorder.stopRecording() {
            // Check minimum duration
            if result.duration >= minimumDuration {
                onRecordingComplete(result.data, result.duration)
            }
            // Clean up the temp file
            audioRecorder.cleanupTempFiles()
        }
    }

    private func cancelRecording() {
        audioRecorder.cancelRecording()
        onRecordingCancelled?()
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - floor(duration)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Audio Level Visualization

struct AudioLevelView: View {
    let level: Float

    private let barCount = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index) / Float(barCount)
        let isActive = level > threshold
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 20

        if isActive {
            let normalizedLevel = min(1, (level - threshold) * Float(barCount))
            return baseHeight + (maxHeight - baseHeight) * CGFloat(normalizedLevel)
        } else {
            return baseHeight
        }
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index) / Float(barCount)
        return level > threshold ? .red : .gray.opacity(0.3)
    }
}

// MARK: - Compact Voice Record Button

/// A more compact version for inline use in message input
struct CompactVoiceRecordButton: View {
    let onRecordingComplete: (Data, TimeInterval) -> Void
    var onRecordingCancelled: (() -> Void)?

    @State private var audioRecorder = AudioRecorderService()
    @State private var isRecording = false
    @State private var dragOffset: CGFloat = 0
    @State private var showCancelZone = false

    private let cancelThreshold: CGFloat = -60

    var body: some View {
        HStack(spacing: 0) {
            // Cancel zone (appears when recording)
            if isRecording {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Cancel")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(showCancelZone ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(16)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Spacer()

            // Recording info
            if isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Text(formatDuration(audioRecorder.recordingDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }

            // Mic button
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                .foregroundColor(isRecording ? .red : .gray)
                .frame(width: 44, height: 44)
                .background(isRecording ? Color.red.opacity(0.1) : Color.clear)
                .clipShape(Circle())
                .offset(x: min(0, dragOffset))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChanged(value)
                        }
                        .onEnded { value in
                            handleDragEnded(value)
                        }
                )
        }
        .animation(.spring(response: 0.3), value: isRecording)
        .onAppear {
            audioRecorder.checkPermission()
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isRecording {
            startRecording()
        }

        dragOffset = value.translation.width
        showCancelZone = dragOffset < cancelThreshold
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if dragOffset < cancelThreshold {
            cancelRecording()
        } else {
            stopRecording()
        }

        dragOffset = 0
        showCancelZone = false
    }

    private func startRecording() {
        Task {
            let success = await audioRecorder.startRecording()
            await MainActor.run {
                isRecording = success
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        if let result = audioRecorder.stopRecording() {
            if result.duration >= 0.5 {
                onRecordingComplete(result.data, result.duration)
            }
            audioRecorder.cleanupTempFiles()
        }
    }

    private func cancelRecording() {
        isRecording = false
        audioRecorder.cancelRecording()
        onRecordingCancelled?()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Voice Message Bubble

/// A bubble view for displaying voice messages in chat
struct VoiceMessageBubble: View {
    let duration: TimeInterval
    let isFromMe: Bool
    let messageId: String
    var audioData: Data?
    var audioURL: URL?

    @State private var audioPlayer = AudioPlayerService()

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button {
                togglePlayback()
            } label: {
                Image(systemName: audioPlayer.isPlaying && audioPlayer.playingMessageId == messageId ? "pause.fill" : "play.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                    .foregroundColor(isFromMe ? .white : .primary)
                    .frame(width: 36, height: 36)
                    .background(isFromMe ? Color.white.opacity(0.2) : Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                // Waveform visualization
                WaveformView(
                    progress: audioPlayer.playingMessageId == messageId ? audioPlayer.progress : 0,
                    isFromMe: isFromMe
                )
                .frame(height: 20)

                // Duration
                Text(formatDuration(audioPlayer.playingMessageId == messageId ? audioPlayer.currentTime : 0) + " / " + formatDuration(duration))
                    .font(.caption2)
                    .foregroundColor(isFromMe ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isFromMe ? Color.blue : Color(.systemGray5))
        .cornerRadius(20)
    }

    private func togglePlayback() {
        if audioPlayer.isPlaying && audioPlayer.playingMessageId == messageId {
            audioPlayer.pause()
        } else if audioPlayer.playingMessageId == messageId {
            audioPlayer.resume()
        } else {
            if let data = audioData {
                audioPlayer.play(data: data, messageId: messageId)
            } else if let url = audioURL {
                audioPlayer.play(url: url, messageId: messageId)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform Visualization

struct WaveformView: View {
    let progress: Double
    let isFromMe: Bool

    private let barCount = 30

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: index))
                        .frame(width: 2, height: barHeight(for: index, in: geometry.size.height))
                }
            }
        }
    }

    private func barHeight(for index: Int, in maxHeight: CGFloat) -> CGFloat {
        // Generate pseudo-random heights based on index for visual effect
        let seed = sin(Double(index) * 0.5) * cos(Double(index) * 0.3)
        let normalized = (seed + 1) / 2 // 0 to 1
        let minHeight: CGFloat = 4
        return minHeight + (maxHeight - minHeight) * CGFloat(normalized * 0.8 + 0.2)
    }

    private func barColor(for index: Int) -> Color {
        let playedThreshold = Double(index) / Double(barCount)
        let isPlayed = progress > playedThreshold

        if isFromMe {
            return isPlayed ? .white : .white.opacity(0.4)
        } else {
            return isPlayed ? .blue : .gray.opacity(0.4)
        }
    }
}

// MARK: - Preview

#Preview("Voice Record Button") {
    VStack(spacing: 40) {
        VoiceRecordButton { data, duration in
            print("Recorded: \(data.count) bytes, \(duration)s")
        }

        CompactVoiceRecordButton { data, duration in
            print("Recorded: \(data.count) bytes, \(duration)s")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))

        HStack {
            VoiceMessageBubble(duration: 12.5, isFromMe: false, messageId: "1")
            Spacer()
        }
        .padding(.horizontal)

        HStack {
            Spacer()
            VoiceMessageBubble(duration: 5.2, isFromMe: true, messageId: "2")
        }
        .padding(.horizontal)
    }
    .padding()
}
