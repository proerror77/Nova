import Foundation
import AVFoundation

// MARK: - Call Recording Service

/// Service for recording voice/video call audio
/// Uses AVAudioRecorder for local audio capture
@MainActor
final class CallRecordingService: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = CallRecordingService()

    // MARK: - Published Properties

    @Published private(set) var isRecording = false
    @Published private(set) var currentRecordingDuration: TimeInterval = 0
    @Published private(set) var recordingError: RecordingError?

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession?
    private var durationTimer: Timer?
    private var currentCallId: String?
    private var recordingStartTime: Date?

    private let fileManager = FileManager.default

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start recording a call
    /// - Parameters:
    ///   - callId: The call ID being recorded
    ///   - audioFormat: Optional audio format settings
    func startRecording(callId: String, audioFormat: AudioFormat = .default) async throws {
        // Check if already recording
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }

        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw RecordingError.permissionDenied
        }

        // Setup audio session
        try setupAudioSession()

        // Create recording URL
        let recordingURL = try createRecordingURL(callId: callId)

        // Configure recorder settings
        let settings = audioFormat.recorderSettings

        // Create audio recorder
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.prepareToRecord() == true else {
                throw RecordingError.preparationFailed
            }

            guard audioRecorder?.record() == true else {
                throw RecordingError.startFailed
            }

            currentCallId = callId
            recordingStartTime = Date()
            isRecording = true
            recordingError = nil

            // Start duration timer
            startDurationTimer()

            #if DEBUG
            print("[CallRecordingService] Started recording call \(callId) to \(recordingURL.path)")
            #endif

        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.recorderInitFailed(error.localizedDescription)
        }
    }

    /// Stop recording the current call
    /// - Returns: URL to the recorded file and metadata
    func stopRecording() throws -> RecordingResult {
        guard isRecording, let recorder = audioRecorder else {
            throw RecordingError.notRecording
        }

        // Stop recording
        recorder.stop()

        // Stop duration timer
        stopDurationTimer()

        let recordingURL = recorder.url
        let duration = currentRecordingDuration
        let callId = currentCallId ?? "unknown"

        // Reset state
        audioRecorder = nil
        currentCallId = nil
        recordingStartTime = nil
        isRecording = false
        currentRecordingDuration = 0

        // Deactivate audio session
        deactivateAudioSession()

        // Get file size
        var fileSize: Int64 = 0
        if let attrs = try? fileManager.attributesOfItem(atPath: recordingURL.path) {
            fileSize = attrs[.size] as? Int64 ?? 0
        }

        #if DEBUG
        print("[CallRecordingService] Stopped recording. Duration: \(duration)s, Size: \(fileSize) bytes")
        #endif

        return RecordingResult(
            callId: callId,
            fileURL: recordingURL,
            duration: duration,
            fileSize: fileSize,
            createdAt: recordingStartTime ?? Date()
        )
    }

    /// Cancel recording without saving
    func cancelRecording() {
        guard isRecording, let recorder = audioRecorder else {
            return
        }

        recorder.stop()
        stopDurationTimer()

        // Delete the partial recording
        let recordingURL = recorder.url
        try? fileManager.removeItem(at: recordingURL)

        // Reset state
        audioRecorder = nil
        currentCallId = nil
        recordingStartTime = nil
        isRecording = false
        currentRecordingDuration = 0

        deactivateAudioSession()

        #if DEBUG
        print("[CallRecordingService] Recording cancelled and deleted")
        #endif
    }

    /// Get all saved recordings
    /// - Returns: Array of recording metadata
    func getSavedRecordings() -> [RecordingMetadata] {
        let recordingsDir = getRecordingsDirectory()
        guard let files = try? fileManager.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]) else {
            return []
        }

        return files.compactMap { url -> RecordingMetadata? in
            guard url.pathExtension == "m4a" else { return nil }

            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let createdAt = attrs?[.creationDate] as? Date ?? Date()
            let fileSize = attrs?[.size] as? Int64 ?? 0

            // Extract call ID from filename (format: call_recording_{callId}_{timestamp}.m4a)
            let filename = url.deletingPathExtension().lastPathComponent
            let parts = filename.components(separatedBy: "_")
            let callId = parts.count >= 3 ? parts[2] : "unknown"

            return RecordingMetadata(
                id: filename,
                callId: callId,
                fileURL: url,
                fileSize: fileSize,
                createdAt: createdAt
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Delete a saved recording
    /// - Parameter recording: Recording metadata to delete
    func deleteRecording(_ recording: RecordingMetadata) throws {
        try fileManager.removeItem(at: recording.fileURL)

        #if DEBUG
        print("[CallRecordingService] Deleted recording: \(recording.id)")
        #endif
    }

    // MARK: - Private Methods

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func setupAudioSession() throws {
        recordingSession = AVAudioSession.sharedInstance()
        try recordingSession?.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try recordingSession?.setActive(true)
    }

    private func deactivateAudioSession() {
        try? recordingSession?.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func createRecordingURL(callId: String) throws -> URL {
        let recordingsDir = getRecordingsDirectory()

        // Create directory if needed
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "call_recording_\(callId)_\(timestamp).m4a"
        return recordingsDir.appendingPathComponent(filename)
    }

    private func getRecordingsDirectory() -> URL {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("CallRecordings", isDirectory: true)
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentRecordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Audio Format

    enum AudioFormat {
        case `default`
        case highQuality
        case compressed

        var recorderSettings: [String: Any] {
            switch self {
            case .default:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
            case .highQuality:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
                    AVEncoderBitRateKey: 256000
                ]
            case .compressed:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 22050,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue,
                    AVEncoderBitRateKey: 64000
                ]
            }
        }
    }

    // MARK: - Result Types

    struct RecordingResult {
        let callId: String
        let fileURL: URL
        let duration: TimeInterval
        let fileSize: Int64
        let createdAt: Date
    }

    struct RecordingMetadata: Identifiable {
        let id: String
        let callId: String
        let fileURL: URL
        let fileSize: Int64
        let createdAt: Date

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }
    }

    // MARK: - Errors

    enum RecordingError: LocalizedError {
        case permissionDenied
        case alreadyRecording
        case notRecording
        case preparationFailed
        case startFailed
        case recorderInitFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission is required to record calls."
            case .alreadyRecording:
                return "A recording is already in progress."
            case .notRecording:
                return "No recording is in progress."
            case .preparationFailed:
                return "Failed to prepare the recorder."
            case .startFailed:
                return "Failed to start recording."
            case .recorderInitFailed(let reason):
                return "Failed to initialize recorder: \(reason)"
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension CallRecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                recordingError = .startFailed
            }

            #if DEBUG
            print("[CallRecordingService] Recording finished, success: \(flag)")
            #endif
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if let error = error {
                recordingError = .recorderInitFailed(error.localizedDescription)
            }

            #if DEBUG
            print("[CallRecordingService] Encoding error: \(error?.localizedDescription ?? "unknown")")
            #endif
        }
    }
}
