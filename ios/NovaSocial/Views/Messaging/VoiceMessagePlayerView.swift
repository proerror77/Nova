import SwiftUI

/// UI for playing voice messages in conversation thread
struct VoiceMessagePlayerView: View {
    @State private var player = AudioPlayerManager()
    @State private var isPlaying = false
    @State private var currentProgress: Double = 0
    @State private var displayTimer: Timer?
    @State private var errorMessage: String?

    let audioURL: URL
    let senderName: String
    let timestamp: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(senderName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(timestamp)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Player controls and waveform
            HStack(spacing: 12) {
                // Play/Pause button
                Button(action: togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                // Waveform and progress
                VStack(spacing: 4) {
                    PlaybackWaveformView(progress: player.progress)
                        .frame(height: 30)

                    HStack(spacing: 8) {
                        Text(formatDuration(player.currentTime))
                            .font(.caption2)
                            .monospacedDigit()

                        ProgressView(value: player.progress)
                            .tint(.blue)

                        Text(formatDuration(player.duration))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Error message if any
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            loadAudio()
        }
        .onDisappear {
            stopPlayback()
            stopUpdateTimer()
        }
    }

    private func loadAudio() {
        // If it's a remote URL, download and play. Otherwise play directly
        if audioURL.scheme == "http" || audioURL.scheme == "https" {
            Task {
                let success = await player.playRemote(url: audioURL)
                if !success {
                    errorMessage = "Failed to load audio"
                }
            }
        } else {
            let success = player.play(url: audioURL)
            if !success {
                errorMessage = "Failed to play audio"
            }
        }
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopUpdateTimer()
        } else {
            // Resume if already playing, otherwise start from beginning
            if player.duration > 0 {
                player.resume()
            } else {
                loadAudio()
            }
            isPlaying = true
            startUpdateTimer()
        }
    }

    private func stopPlayback() {
        player.stop()
        isPlaying = false
        currentProgress = 0
        stopUpdateTimer()
    }

    private func startUpdateTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Timer updates the UI through the player's @Observable properties
            // which automatically trigger view updates
        }
    }

    private func stopUpdateTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

/// Animated playback waveform visualization
struct PlaybackWaveformView: View {
    let progress: Double

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<25, id: \.self) { index in
                VStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(waveformColor(for: index))
                        .frame(height: waveformHeight(for: index))
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = CGFloat(Int.random(in: 8...16))
        let progressIndex = CGFloat(index) / 25.0

        // Bars before progress are full height
        if progressIndex < progress {
            return baseHeight
        } else {
            // Bars after progress are at 30% height
            return baseHeight * 0.3
        }
    }

    private func waveformColor(for index: Int) -> Color {
        let progressIndex = CGFloat(index) / 25.0
        if progressIndex < progress {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
}

#Preview {
    VoiceMessagePlayerView(
        audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
        senderName: "John Doe",
        timestamp: "2:45 PM"
    )
    .padding()
    .background(Color(.systemBackground))
}
