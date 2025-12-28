import SwiftUI
import AVFoundation

// MARK: - Call Recordings View

/// View for managing saved call recordings
struct CallRecordingsView: View {
    @Binding var currentPage: AppPage

    @State private var recordings: [CallRecordingService.RecordingMetadata] = []
    @State private var isLoading = true
    @State private var playingRecordingId: String?
    @State private var showDeleteConfirmation = false
    @State private var recordingToDelete: CallRecordingService.RecordingMetadata?
    @State private var errorMessage: String?

    private let recordingService = CallRecordingService.shared
    @StateObject private var audioPlayer = AudioPlayerManager()

    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                if isLoading {
                    loadingView
                } else if recordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsList
                }
            }
        }
        .onAppear {
            loadRecordings()
        }
        .alert("Delete Recording", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                recordingToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let recording = recordingToDelete {
                    deleteRecording(recording)
                }
            }
        } message: {
            Text("Are you sure you want to delete this recording? This action cannot be undone.")
        }
        .overlay(alignment: .top) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.9))
                    .cornerRadius(8)
                    .padding(.top, 8)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            errorMessage = nil
                        }
                    }
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button(action: {
                currentPage = .setting
            }) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .foregroundColor(DesignTokens.textPrimary)
            }

            Spacer()

            Text("Call Recordings")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignTokens.textPrimary)

            Spacer()

            Color.clear
                .frame(width: 24)
        }
        .frame(height: DesignTokens.topBarHeight)
        .padding(.horizontal, 16)
        .background(DesignTokens.surface)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading recordings...")
                .foregroundColor(DesignTokens.textSecondary)
            Spacer()
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 60))
                .foregroundColor(DesignTokens.textSecondary.opacity(0.5))

            Text("No Recordings")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DesignTokens.textPrimary)

            Text("Call recordings will appear here.\nYou can record calls using the record button during a call.")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(recordings) { recording in
                    RecordingRow(
                        recording: recording,
                        isPlaying: playingRecordingId == recording.id,
                        onPlay: { playRecording(recording) },
                        onStop: { stopPlayback() },
                        onShare: { shareRecording(recording) },
                        onDelete: {
                            recordingToDelete = recording
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
        }
    }

    // MARK: - Actions

    private func loadRecordings() {
        isLoading = true
        recordings = recordingService.getSavedRecordings()
        isLoading = false
    }

    private func playRecording(_ recording: CallRecordingService.RecordingMetadata) {
        if playingRecordingId == recording.id {
            stopPlayback()
        } else {
            stopPlayback()
            audioPlayer.play(url: recording.fileURL)
            playingRecordingId = recording.id
        }
    }

    private func stopPlayback() {
        audioPlayer.stop()
        playingRecordingId = nil
    }

    private func shareRecording(_ recording: CallRecordingService.RecordingMetadata) {
        let activityVC = UIActivityViewController(
            activityItems: [recording.fileURL],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func deleteRecording(_ recording: CallRecordingService.RecordingMetadata) {
        do {
            try recordingService.deleteRecording(recording)
            recordings.removeAll { $0.id == recording.id }
            recordingToDelete = nil
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }
}

// MARK: - Recording Row

private struct RecordingRow: View {
    let recording: CallRecordingService.RecordingMetadata
    let isPlaying: Bool
    let onPlay: () -> Void
    let onStop: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Play/Stop button
                Button(action: isPlaying ? onStop : onPlay) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(isPlaying ? .red : DesignTokens.accentColor)
                }

                // Recording info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Call Recording")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(dateFormatter.string(from: recording.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textSecondary)

                    Text(recording.formattedSize)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 16) {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(DesignTokens.accentColor)
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(16)
        }
        .background(DesignTokens.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPlaying ? DesignTokens.accentColor : Color.gray.opacity(0.3), lineWidth: isPlaying ? 2 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Audio Player Manager

private class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false

    func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("[AudioPlayerManager] Error playing audio: \(error)")
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

// MARK: - Preview

#Preview {
    CallRecordingsView(currentPage: .constant(.callRecordings))
}
