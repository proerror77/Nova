import Foundation
import AVFoundation
import Observation

/// Manages audio playback with progress tracking
@Observable
final class AudioPlayerManager: NSObject, AVAudioPlayerDelegate, Sendable {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var currentURL: URL?

    nonisolated private let lock = NSLock()

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: []
            )
            try audioSession.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    /// Load and start playing audio from URL
    func play(url: URL) -> Bool {
        stop()

        do {
            let audioData = try Data(contentsOf: url)
            audioPlayer = try AVAudioPlayer(data: audioData, fileTypeHint: .m4a)
            audioPlayer?.delegate = self

            guard let player = audioPlayer, player.play() else {
                return false
            }

            lock.withLock {
                isPlaying = true
                currentURL = url
                duration = player.duration
                currentTime = 0
            }

            startProgressTracking()
            return true
        } catch {
            print("Failed to load audio: \(error)")
            return false
        }
    }

    /// Play from remote URL (download first)
    func playRemote(url: URL) async -> Bool {
        do {
            let audioData = try await URLSession.shared.data(from: url).0
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("audio_\(UUID().uuidString).m4a")

            try audioData.write(to: tempURL)
            return play(url: tempURL)
        } catch {
            print("Failed to download audio: \(error)")
            return false
        }
    }

    /// Pause audio playback
    func pause() {
        guard isPlaying else { return }

        audioPlayer?.pause()
        lock.withLock { isPlaying = false }
    }

    /// Resume audio playback
    func resume() {
        guard !isPlaying, let player = audioPlayer else { return }

        guard player.play() else { return }
        lock.withLock { isPlaying = true }
    }

    /// Stop audio playback
    func stop() {
        displayLink?.invalidate()
        displayLink = nil

        audioPlayer?.stop()

        lock.withLock {
            isPlaying = false
            currentTime = 0
            duration = 0
            currentURL = nil
        }
    }

    /// Seek to specific time
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }

        player.currentTime = min(time, player.duration)
        lock.withLock { currentTime = player.currentTime }
    }

    /// Get progress ratio (0.0 to 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    // MARK: - Private Methods

    private func startProgressTracking() {
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateProgress)
        )
        displayLink?.preferredFramesPerSecond = 2
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateProgress() {
        guard isPlaying, let player = audioPlayer else { return }

        lock.withLock {
            currentTime = player.currentTime
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        DispatchQueue.main.async {
            self.displayLink?.invalidate()
            self.displayLink = nil

            self.lock.withLock {
                self.isPlaying = false
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        if let error = error {
            print("Audio decoding error: \(error)")
        }
    }
}
