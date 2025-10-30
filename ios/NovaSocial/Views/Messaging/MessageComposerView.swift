import SwiftUI

struct MessageComposerView: View {
    @Binding var text: String
    let onSend: () -> Void
    let onSendVoiceMessage: (URL) -> Void

    @State private var recorder = AudioRecorderManager()
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var displayTimer: Timer?
    @State private var dragOffset: CGFloat = 0
    @State private var recordingState: RecordingState = .recording

    enum RecordingState {
        case recording      // 正在录制
        case readyToCancel  // 可以取消（上滑）
    }

    var body: some View {
        ZStack {
            // Main message composer
            HStack(spacing: 12) {
                // Voice message button - long press to record
                VoiceButtonView(isRecording: isRecording)
                    .onLongPressGesture(minimumDuration: 0.3) {
                        startRecording()
                    }

                // Text input
                TextField("Type a message", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSend)
                    .disabled(isRecording)

                // Send button
                Button("Send", action: onSend)
                    .disabled(text.isEmpty || isRecording)
            }
            .padding(.horizontal, 8)
            .opacity(isRecording ? 0.5 : 1.0)

            // WeChat-style floating recorder bubble
            if isRecording {
                ZStack(alignment: .center) {
                    // Semi-transparent background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    // Floating recording bubble
                    VStack(spacing: 12) {
                        // Recording indicator with pulsing dot
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                                .scaleEffect(1.3)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)

                            Text(recordingState == .readyToCancel ? "上滑取消" : "松开发送")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                        }
                        .padding(.top, 12)

                        // Duration display
                        Text(formatDuration(recordingDuration))
                            .font(.system(size: 32, weight: .semibold, design: .monospaced))
                            .foregroundColor(.black)

                        // Animated waveform
                        WaveformVisualizerView(level: recorder.currentLevel)
                            .frame(height: 45)

                        // Hint text
                        HStack(spacing: 4) {
                            Image(systemName: recordingState == .readyToCancel ? "hand.raised.fill" : "mic.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)

                            Text(recordingState == .readyToCancel ? "上滑取消录制" : "按住说话，松开发送")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.bottom, 12)
                    }
                    .frame(width: 140, height: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation.height

                                // 上滑超过50pt时显示取消提示
                                if value.translation.height < -50 {
                                    recordingState = .readyToCancel
                                } else {
                                    recordingState = .recording
                                }
                            }
                            .onEnded { value in
                                if value.translation.height < -50 {
                                    // 上滑取消
                                    cancelRecording()
                                } else {
                                    // 松开发送
                                    sendRecording()
                                }
                                dragOffset = 0
                            }
                    )
                }
            }
        }
    }

    private func startRecording() {
        if recorder.startRecording() {
            isRecording = true
            recordingDuration = 0
            recordingState = .recording
            dragOffset = 0
            startTimer()
        }
    }

    private func sendRecording() {
        stopTimer()
        isRecording = false

        if let audioURL = recorder.stopRecording() {
            onSendVoiceMessage(audioURL)
        }
    }

    private func cancelRecording() {
        stopTimer()
        isRecording = false
        recorder.cancelRecording()
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

/// Custom voice button with visual feedback
struct VoiceButtonView: View {
    let isRecording: Bool

    var body: some View {
        Image(systemName: "mic.circle.fill")
            .font(.title2)
            .foregroundColor(isRecording ? .red : .blue)
            .padding(8)
            .scaleEffect(isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
    }
}

#Preview {
    MessageComposerView(
        text: .constant(""),
        onSend: { },
        onSendVoiceMessage: { _ in }
    )
}

