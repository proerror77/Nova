import Foundation
import Speech
import AVFoundation

// MARK: - Speech Recognition Service

/// 語音轉文字服務 - 使用 iOS Speech 框架
@MainActor
@Observable
final class SpeechRecognitionService {
    // MARK: - Singleton

    static let shared = SpeechRecognitionService()

    // MARK: - Properties

    /// 識別結果文字
    private(set) var recognizedText: String = ""

    /// 是否正在識別
    private(set) var isRecognizing = false

    /// 識別錯誤
    private(set) var errorMessage: String?

    /// 權限狀態
    private(set) var isAuthorized = false

    // MARK: - Private Properties

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Initialization

    private init() {
        // 使用繁體中文識別器，fallback 到系統語言
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hant-TW"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans-CN"))
            ?? SFSpeechRecognizer()

        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// 檢查授權狀態
    func checkAuthorizationStatus() {
        let status = SFSpeechRecognizer.authorizationStatus()
        isAuthorized = (status == .authorized)
    }

    /// 請求語音識別權限
    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.isAuthorized = (status == .authorized)
                    continuation.resume(returning: self.isAuthorized)
                }
            }
        }
    }

    // MARK: - Recognition from Audio File

    /// 從音頻文件識別文字
    /// - Parameter url: 音頻文件 URL
    /// - Returns: 識別的文字
    func recognizeFromFile(url: URL) async throws -> String {
        if !isAuthorized {
            let granted = await requestAuthorization()
            guard granted else {
                throw SpeechRecognitionError.notAuthorized
            }
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerNotAvailable
        }

        isRecognizing = true
        recognizedText = ""
        errorMessage = nil

        defer {
            isRecognizing = false
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.taskHint = .dictation

            // 設置語言偏好
            if #available(iOS 16, *) {
                request.addsPunctuation = true
            }

            recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        continuation.resume(throwing: SpeechRecognitionError.recognitionFailed(error.localizedDescription))
                        return
                    }

                    if let result = result, result.isFinal {
                        let text = result.bestTranscription.formattedString
                        self?.recognizedText = text
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }

    // MARK: - Real-time Recognition

    /// 開始實時語音識別
    func startRealTimeRecognition() async throws {
        guard isAuthorized else {
            let granted = await requestAuthorization()
            if !granted {
                throw SpeechRecognitionError.notAuthorized
            }
            // 如果授權成功，繼續執行
            return try await startRealTimeRecognition()
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerNotAvailable
        }

        // 停止之前的任務
        stopRecognition()

        recognizedText = ""
        errorMessage = nil
        isRecognizing = true

        // 配置音頻會話
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // 創建識別請求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }

        // 配置音頻輸入
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        // 開始識別任務
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                }

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.stopRecognition()
                }
            }
        }

        // 啟動音頻引擎
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// 停止語音識別
    func stopRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isRecognizing = false
    }

    /// 重置狀態
    func reset() {
        stopRecognition()
        recognizedText = ""
        errorMessage = nil
    }
}

// MARK: - Errors

enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case recognizerNotAvailable
    case requestCreationFailed
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "需要語音識別權限才能使用此功能"
        case .recognizerNotAvailable:
            return "語音識別服務暫時不可用"
        case .requestCreationFailed:
            return "無法創建語音識別請求"
        case .recognitionFailed(let reason):
            return "語音識別失敗：\(reason)"
        }
    }
}
