import SwiftUI

/// WeChat-style voice recording with long press, drag to cancel, and floating bubble UI
struct WeChatStyleVoiceRecorderView: View {
    @State private var recorder = AudioRecorderManager()
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var displayTimer: Timer?
    @State private var dragHeight: CGFloat = 0
    @State private var showCancelHint = false
    @State private var recordingState: RecordingState = .idle

    enum RecordingState {
        case idle           // 未开始
        case recording      // 正在录制
        case readyToCancel  // 可以取消（上滑）
    }

    let onRecordingComplete: (URL) -> Void

    var body: some View {
        ZStack {
            // Floating recording bubble (when recording)
            if isRecording {
                recordingBubble
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var recordingBubble: some View {
        VStack(spacing: 16) {
            // Recording indicator
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                    .scaleEffect(isRecording ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)

                Text(recordingState == .readyToCancel ? "上滑取消" : "松开发送")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
            }
            .padding(.top, 16)

            // Duration
            Text(formatDuration(recordingDuration))
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .foregroundColor(.black)

            // Waveform
            WaveformVisualizerView(level: recorder.currentLevel)
                .frame(height: 50)

            // State indicator
            HStack(spacing: 8) {
                Image(systemName: recordingState == .readyToCancel ? "hand.raised.fill" : "mic.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)

                Text(recordingState == .readyToCancel ? "上滑即可取消录制" : "按住说话，松开发送")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 140, height: 200)
        .background(Color(.systemGray6))
        .cornerRadius(20)
        .shadow(radius: 10)
        .offset(y: dragHeight)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragHeight = value.translation.height

                    // 上滑超过50pt时显示取消提示
                    if value.translation.height < -50 {
                        showCancelHint = true
                        recordingState = .readyToCancel
                    } else {
                        showCancelHint = false
                        recordingState = .recording
                    }
                }
                .onEnded { value in
                    // 上滑取消
                    if value.translation.height < -50 {
                        cancelRecording()
                    } else {
                        // 松开发送
                        sendRecording()
                    }
                    dragHeight = 0
                    showCancelHint = false
                }
        )
    }

    /// Long press gesture for the record button (to be called from MessageComposerView)
    func createLongPressGesture() -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                startRecording()
            }
    }

    private func startRecording() {
        if recorder.startRecording() {
            isRecording = true
            recordingState = .recording
            recordingDuration = 0
            startTimer()
        }
    }

    private func sendRecording() {
        stopTimer()
        isRecording = false

        if let audioURL = recorder.stopRecording() {
            onRecordingComplete(audioURL)
        }
    }

    private func cancelRecording() {
        stopTimer()
        isRecording = false
        recorder.cancelRecording()
        recordingState = .idle
    }

    private func startTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration = recorder.currentDuration
        }
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

#Preview {
    WeChatStyleVoiceRecorderView(
        onRecordingComplete: { _ in }
    )
}
