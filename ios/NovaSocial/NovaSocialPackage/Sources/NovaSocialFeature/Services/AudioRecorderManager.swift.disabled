import Foundation
import AVFoundation
import Observation

/// Manages audio recording with real-time level monitoring
@Observable
final class AudioRecorderManager: NSObject, AVAudioRecorderDelegate, Sendable {
    private(set) var isRecording = false
    private(set) var recordedURL: URL?
    private(set) var durationSeconds: TimeInterval = 0
    private(set) var currentLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var displayLink: CADisplayLink?
    private var startTime: Date?

    nonisolated private let lock = NSLock()

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .record,
                mode: .default,
                options: [.duckOthers, .defaultToSpeaker]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    /// Start recording audio with Opus codec
    func startRecording() -> Bool {
        guard !isRecording else { return false }

        let tempDir = FileManager.default.temporaryDirectory
        let filename = "voice_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
            AVEncoderQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.record() == true else {
                return false
            }

            lock.withLock {
                isRecording = true
                recordedURL = fileURL
                durationSeconds = 0
                startTime = Date()
            }

            startMetering()
            return true
        } catch {
            print("Failed to start recording: \(error)")
            return false
        }
    }

    /// Stop recording and return the audio file URL
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        displayLink?.invalidate()
        displayLink = nil

        audioRecorder?.stop()

        let url = lock.withLock { () -> URL? in
            isRecording = false
            let recorded = recordedURL
            recordedURL = nil
            return recorded
        }

        return url
    }

    /// Cancel recording and delete the file
    func cancelRecording() {
        guard isRecording else { return }

        displayLink?.invalidate()
        displayLink = nil

        audioRecorder?.stop()

        lock.withLock {
            if let url = recordedURL {
                try? FileManager.default.removeItem(at: url)
            }
            isRecording = false
            recordedURL = nil
        }
    }

    /// Get current recording duration
    var currentDuration: TimeInterval {
        guard isRecording else { return 0 }
        return Date().timeIntervalSince(startTime ?? Date())
    }

    // MARK: - Private Methods

    private func startMetering() {
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateMetering)
        )
        displayLink?.preferredFramesPerSecond = 10
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateMetering() {
        guard isRecording else { return }

        audioRecorder?.updateMeters()

        let level = audioRecorder?.averagePower(forChannel: 0) ?? -160
        let normalizedLevel = normalizeLevel(level)

        lock.withLock {
            currentLevel = normalizedLevel
            durationSeconds = currentDuration
        }
    }

    private func normalizeLevel(_ dB: Float) -> Float {
        // Convert dB range (-160 to 0) to normalized range (0 to 1)
        let normalized = (dB + 160) / 160
        return max(0, min(1, normalized))
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        if !flag {
            print("Audio recording failed")
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        if let error = error {
            print("Audio encoding error: \(error)")
        }
    }
}
