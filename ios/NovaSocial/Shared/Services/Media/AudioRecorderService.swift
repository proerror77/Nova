import Foundation
import AVFoundation
import Combine

// MARK: - Audio Recorder Service

/// Service for recording voice messages
/// Handles microphone permissions, audio recording, and file management
@Observable
final class AudioRecorderService: NSObject {
    // MARK: - Properties

    /// Current recording state
    private(set) var isRecording = false

    /// Recording duration in seconds
    private(set) var recordingDuration: TimeInterval = 0

    /// Audio level for visualization (0.0 - 1.0)
    private(set) var audioLevel: Float = 0

    /// Error message if recording fails
    private(set) var errorMessage: String?

    /// Permission status
    private(set) var permissionGranted = false

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession?
    private var recordingURL: URL?
    private var durationTimer: Timer?
    private var levelTimer: Timer?

    // Recording settings optimized for voice messages
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        AVEncoderBitRateKey: 128000
    ]

    // MARK: - Initialization

    override init() {
        super.init()
        checkPermission()
    }

    // MARK: - Permission Management

    /// Check current microphone permission status
    func checkPermission() {
        // Use AVAudioApplication for iOS 17+
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionGranted = true
        case .denied:
            permissionGranted = false
        case .undetermined:
            permissionGranted = false
        @unknown default:
            permissionGranted = false
        }
    }

    /// Request microphone permission
    func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        await MainActor.run {
            self.permissionGranted = granted
        }
        return granted
    }

    // MARK: - Recording Control

    /// Start recording a voice message
    /// - Returns: True if recording started successfully
    @MainActor
    func startRecording() async -> Bool {
        // Check permission first
        if !permissionGranted {
            let granted = await requestPermission()
            if !granted {
                errorMessage = "Microphone permission denied"
                return false
            }
        }

        // Setup audio session
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession?.setActive(true)
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
            #if DEBUG
            print("[AudioRecorder] Audio session error: \(error)")
            #endif
            return false
        }

        // Create recording URL
        let fileName = "voice_\(UUID().uuidString).m4a"
        let documentsPath = FileManager.default.temporaryDirectory
        recordingURL = documentsPath.appendingPathComponent(fileName)

        guard let url = recordingURL else {
            errorMessage = "Failed to create recording file"
            return false
        }

        // Setup and start recorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()

            isRecording = true
            recordingDuration = 0
            errorMessage = nil

            // Start timers for duration and audio level
            startTimers()

            #if DEBUG
            print("[AudioRecorder] Recording started: \(url.lastPathComponent)")
            #endif

            return true
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            #if DEBUG
            print("[AudioRecorder] Recording error: \(error)")
            #endif
            return false
        }
    }

    /// Stop recording and return the audio file data
    /// - Returns: Tuple of (audio data, duration in seconds) or nil if failed
    @MainActor
    func stopRecording() -> (data: Data, duration: TimeInterval, url: URL)? {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
            return nil
        }

        let duration = recorder.currentTime
        recorder.stop()

        stopTimers()
        isRecording = false

        // Deactivate audio session
        try? audioSession?.setActive(false)

        // Read recorded file
        do {
            let data = try Data(contentsOf: url)

            #if DEBUG
            print("[AudioRecorder] Recording stopped: \(data.count / 1024) KB, duration: \(String(format: "%.1f", duration))s")
            #endif

            return (data: data, duration: duration, url: url)
        } catch {
            errorMessage = "Failed to read recording: \(error.localizedDescription)"
            #if DEBUG
            print("[AudioRecorder] Failed to read recording: \(error)")
            #endif
            return nil
        }
    }

    /// Cancel recording without saving
    @MainActor
    func cancelRecording() {
        guard isRecording else { return }

        audioRecorder?.stop()
        stopTimers()
        isRecording = false
        recordingDuration = 0

        // Delete the recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        try? audioSession?.setActive(false)

        #if DEBUG
        print("[AudioRecorder] Recording cancelled")
        #endif
    }

    /// Clean up temporary recording files
    func cleanupTempFiles() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    // MARK: - Private Methods

    private func startTimers() {
        // Duration timer - update every 0.1 seconds
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                self.recordingDuration = recorder.currentTime
            }
        }

        // Level timer - update every 0.05 seconds for smooth visualization
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                recorder.updateMeters()

                // Convert decibels to linear scale (0.0 - 1.0)
                let decibels = recorder.averagePower(forChannel: 0)
                // Typical range is -160 to 0, normalize to 0-1
                let normalizedLevel = max(0, min(1, (decibels + 60) / 60))
                self.audioLevel = normalizedLevel
            }
        }
    }

    private func stopTimers() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }

    deinit {
        stopTimers()
        cleanupTempFiles()
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorderService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.errorMessage = "Recording failed"
                self.isRecording = false
            }
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.errorMessage = "Recording encode error: \(error?.localizedDescription ?? "Unknown")"
            self.isRecording = false
        }
        #if DEBUG
        print("[AudioRecorder] Encode error: \(error?.localizedDescription ?? "Unknown")")
        #endif
    }
}

// MARK: - Audio Player Service

/// Service for playing voice messages
@Observable
final class AudioPlayerService: NSObject {
    // MARK: - Properties

    /// Current playback state
    private(set) var isPlaying = false

    /// Current playback time in seconds
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of current audio
    private(set) var duration: TimeInterval = 0

    /// Playback progress (0.0 - 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// Currently playing message ID
    private(set) var playingMessageId: String?

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    // MARK: - Playback Control

    /// Play audio from URL
    /// - Parameters:
    ///   - url: URL of the audio file
    ///   - messageId: ID of the message being played
    @MainActor
    func play(url: URL, messageId: String) {
        // Stop any current playback
        stop()

        do {
            // Setup audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            isPlaying = true
            playingMessageId = messageId

            startProgressTimer()

            #if DEBUG
            print("[AudioPlayer] Playing: \(url.lastPathComponent), duration: \(String(format: "%.1f", duration))s")
            #endif
        } catch {
            #if DEBUG
            print("[AudioPlayer] Play error: \(error)")
            #endif
        }
    }

    /// Play audio from Data
    /// - Parameters:
    ///   - data: Audio data
    ///   - messageId: ID of the message being played
    @MainActor
    func play(data: Data, messageId: String) {
        stop()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            isPlaying = true
            playingMessageId = messageId

            startProgressTimer()
        } catch {
            #if DEBUG
            print("[AudioPlayer] Play error: \(error)")
            #endif
        }
    }

    /// Pause current playback
    @MainActor
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    /// Resume paused playback
    @MainActor
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startProgressTimer()
    }

    /// Stop playback
    @MainActor
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playingMessageId = nil
        stopProgressTimer()

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    /// Seek to specific time
    /// - Parameter time: Time in seconds
    @MainActor
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    // MARK: - Private Methods

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    deinit {
        stopProgressTimer()
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.playingMessageId = nil
            self.stopProgressTimer()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
            self.playingMessageId = nil
            self.stopProgressTimer()
        }
        #if DEBUG
        print("[AudioPlayer] Decode error: \(error?.localizedDescription ?? "Unknown")")
        #endif
    }
}
