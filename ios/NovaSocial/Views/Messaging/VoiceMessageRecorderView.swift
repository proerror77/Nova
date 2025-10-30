import SwiftUI

/// UI for recording voice messages with real-time visualization
struct VoiceMessageRecorderView: View {
    @State private var recorder = AudioRecorderManager()
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var displayTimer: Timer?

    let onRecordingComplete: (URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Voice Message")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .padding()

            // Waveform visualization (mic level)
            VStack(spacing: 12) {
                Text(formatDuration(recordingDuration))
                    .font(.title2)
                    .monospacedDigit()

                WaveformVisualizerView(level: recorder.currentLevel)
                    .frame(height: 60)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Recording status
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .foregroundColor(.red)
                    .scaleEffect(isRecording ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)

                Text(isRecording ? "Recording..." : "Ready to record")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            // Control buttons
            HStack(spacing: 16) {
                // Cancel button
                Button(action: {
                    stopRecording(save: false)
                    onCancel()
                }) {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Cancel")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(.systemGray4))
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(!isRecording)

                // Record/Stop button
                Button(action: {
                    if isRecording {
                        stopRecording(save: false)
                    } else {
                        startRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: isRecording ? "pause.fill" : "record.circle.fill")
                        Text(isRecording ? "Stop" : "Record")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(isRecording ? Color.orange : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                // Send button
                Button(action: {
                    stopRecording(save: true)
                }) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(!isRecording && recordingDuration == 0)
            }
            .padding()

            Spacer()
        }
        .background(Color(.systemBackground))
        .onDisappear {
            stopTimer()
            if isRecording {
                recorder.cancelRecording()
            }
        }
    }

    private func startRecording() {
        if recorder.startRecording() {
            isRecording = true
            recordingDuration = 0
            startTimer()
        }
    }

    private func stopRecording(save: Bool) {
        stopTimer()
        isRecording = false

        if save, let audioURL = recorder.stopRecording() {
            onRecordingComplete(audioURL)
        } else {
            recorder.cancelRecording()
        }
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

/// Animated waveform visualization
struct WaveformVisualizerView: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                VStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .cyan]),
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                        )
                        .frame(height: CGFloat(level) * CGFloat(30) + CGFloat(index % 2) * 5)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VoiceMessageRecorderView(
        onRecordingComplete: { _ in },
        onCancel: { }
    )
}
