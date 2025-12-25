import SwiftUI
import PhotosUI
import CoreLocation
import AVFoundation

// MARK: - Message Send Error
enum MessageSendError: Error {
    case timeout
}

// MARK: - ChatViewModel
/// ViewModel for ChatView - handles all state and business logic for chat conversations
/// Uses MatrixBridgeService for E2EE messaging

@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Configuration

    private(set) var conversationId: String = ""
    private(set) var userName: String = "User"
    private(set) var otherUserAvatarUrl: String?

    // MARK: - Services

    private let matrixBridge = MatrixBridgeService.shared
    private(set) var messageSender: ChatMessageSender?
    let audioRecorder = AudioRecorderService()
    let audioPlayer = AudioPlayerService()

    // MARK: - Message State

    var messageText = ""
    var messages: [ChatMessage] = []

    // MARK: - UI State

    var showUserProfile = false
    var showAttachmentOptions = false
    var showCamera = false
    var showVoiceCall = false
    var showVideoCall = false
    var showFilePicker = false
    var showLocationAlert = false
    var showCameraPermissionAlert = false
    var showMicrophonePermissionAlert = false

    // MARK: - Media State

    var selectedPhotoItem: PhotosPickerItem?
    var cameraImage: UIImage?

    // MARK: - Loading States

    var isLoadingHistory = false
    var isSending = false
    var isUploadingImage = false
    var isUploadingFile = false
    var isRecordingVoice = false
    var isPreviewMode = false

    // MARK: - Matrix E2EE

    var isMatrixE2EEEnabled = false

    // MARK: - Pagination

    var hasMoreMessages = true
    var nextCursor: String?

    // MARK: - Error State

    var error: String?

    // MARK: - Voice Recording

    var voiceRecordDragOffset: CGFloat = 0
    let voiceCancelThreshold: CGFloat = -60

    // MARK: - Internal State

    private var matrixMessageHandlerSetup = false

    // MARK: - Callbacks

    var onDismiss: (() -> Void)?

    // MARK: - Dependencies

    private weak var typingHandler: ChatTypingHandler?

    // MARK: - Computed Properties

    var currentUserId: String {
        KeychainService.shared.get(.userId) ?? "unknown"
    }

    var currentUserAvatarUrl: String? {
        AuthenticationManager.shared.currentUser?.avatarUrl
    }

    // MARK: - Static Properties

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        return formatter
    }()

    #if DEBUG
    private static var useChatPreviewMode: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return false
        #endif
    }

    private static var mockMessages: [ChatMessage] {
        [
            ChatMessage(localText: "Hello, how are you bro~", isFromMe: false),
            ChatMessage(localText: "Have you been busy recently?", isFromMe: false),
            ChatMessage(localText: "Not bad. There's a new project recently and I'm extremely busy", isFromMe: true),
            ChatMessage(localText: "Is there dinner time tonight? There is a project that you might be interested in", isFromMe: false),
        ]
    }
    #endif

    // MARK: - Initialization

    init() {}

    func configure(
        conversationId: String,
        userName: String,
        otherUserAvatarUrl: String?,
        typingHandler: ChatTypingHandler,
        onDismiss: (() -> Void)? = nil
    ) {
        self.conversationId = conversationId
        self.userName = userName
        self.otherUserAvatarUrl = otherUserAvatarUrl
        self.typingHandler = typingHandler
        self.onDismiss = onDismiss

        // Initialize message sender
        self.messageSender = ChatMessageSender(
            chatService: ChatService.shared,
            conversationId: conversationId
        )

        setupMessageSenderCallbacks()
    }

    // MARK: - Message Sender Callbacks

    private func setupMessageSenderCallbacks() {
        messageSender?.onMessageAdded = { [weak self] message in
            Task { @MainActor in
                self?.messages.append(message)
            }
        }

        messageSender?.onMessageUpdated = { [weak self] localId, updatedMessage in
            Task { @MainActor in
                if let index = self?.messages.firstIndex(where: { $0.id == localId }) {
                    self?.messages[index] = updatedMessage
                }
            }
        }

        messageSender?.onMessageRemoved = { [weak self] messageId in
            Task { @MainActor in
                self?.messages.removeAll { $0.id == messageId }
            }
        }

        messageSender?.onSendingStateChanged = { [weak self] isSending in
            Task { @MainActor in
                self?.isSending = isSending
            }
        }

        messageSender?.onUploadingStateChanged = { [weak self] isUploading in
            Task { @MainActor in
                self?.isUploadingImage = isUploading
            }
        }

        messageSender?.onError = { [weak self] errorMessage in
            Task { @MainActor in
                self?.error = errorMessage
            }
        }

        messageSender?.currentUserId = { [weak self] in
            self?.currentUserId ?? "unknown"
        }
    }

    // MARK: - Load Chat Data

    func loadChatData(retryCount: Int = 0) async {
        #if DEBUG
        if Self.useChatPreviewMode {
            print("🎨 [ChatViewModel] Preview Mode enabled - using mock data")
            messages = Self.mockMessages
            isLoadingHistory = false
            error = nil
            isPreviewMode = true
            return
        }
        #endif

        isPreviewMode = false
        isLoadingHistory = true
        error = nil

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            isMatrixE2EEEnabled = matrixBridge.isInitialized

            setupMatrixMessageHandler()

            let matrixMessages = try await matrixBridge.getMessages(conversationId: conversationId, limit: 50)
            let sorted = matrixMessages.sorted { $0.timestamp < $1.timestamp }
            messages = sorted.map { matrixMessage in
                let novaMessage = matrixBridge.convertToNovaMessage(matrixMessage, conversationId: conversationId)
                return ChatMessage(from: novaMessage, currentUserId: currentUserId)
            }

            hasMoreMessages = matrixMessages.count >= 50
            nextCursor = nil

            try? await matrixBridge.markAsRead(conversationId: conversationId)

            #if DEBUG
            print("[ChatViewModel] Loaded \(messages.count) Matrix messages for room \(conversationId)")
            #endif
        } catch {
            if matrixBridge.handleMatrixError(error) && retryCount < 1 {
                #if DEBUG
                print("[ChatViewModel] Database corruption detected, retrying with fresh session...")
                #endif
                try? await matrixBridge.initialize()
                await loadChatData(retryCount: retryCount + 1)
                return
            }

            self.error = "Failed to load messages: \(error.localizedDescription)"
            #if DEBUG
            print("[ChatViewModel] Load error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }

    // MARK: - Matrix Message Handler

    private func setupMatrixMessageHandler() {
        guard !matrixMessageHandlerSetup else {
            #if DEBUG
            print("[ChatViewModel] ⚠️ Matrix message handler already setup, skipping")
            #endif
            return
        }

        matrixMessageHandlerSetup = true

        MatrixBridgeService.shared.onMatrixMessage = { [weak self] conversationId, matrixMessage in
            Task { @MainActor in
                guard let self = self else { return }
                guard conversationId == self.conversationId else { return }

                // Skip own messages (avoid duplicate with optimistic update)
                if let myMatrixId = MatrixBridgeService.shared.matrixUserId,
                   matrixMessage.senderId == myMatrixId {
                    #if DEBUG
                    print("[ChatViewModel] ✅ Skipping own message from Matrix sync: \(matrixMessage.id)")
                    #endif
                    return
                }

                // Avoid duplicates
                if self.messages.contains(where: { $0.id == matrixMessage.id }) {
                    #if DEBUG
                    print("[ChatViewModel] ⚠️ Skipping duplicate message: \(matrixMessage.id)")
                    #endif
                    return
                }

                let novaMessage = MatrixBridgeService.shared.convertToNovaMessage(
                    matrixMessage,
                    conversationId: conversationId
                )

                let newChatMessage = ChatMessage(from: novaMessage, currentUserId: self.currentUserId)

                // Double-check for race conditions
                if self.messages.contains(where: { $0.id == newChatMessage.id }) {
                    return
                }

                self.messages.append(newChatMessage)

                #if DEBUG
                print("[ChatViewModel] ✅ Message added - ID: \(newChatMessage.id), Total: \(self.messages.count)")
                #endif

                // Clear typing indicator
                self.typingHandler?.stopTypingIndicator()

                // Mark as read
                if novaMessage.senderId != self.currentUserId {
                    try? await self.matrixBridge.markAsRead(conversationId: self.conversationId)
                }
            }
        }

        // Matrix typing indicator
        MatrixBridgeService.shared.onTypingIndicator = { [weak self] conversationId, userIds in
            Task { @MainActor in
                guard let self = self else { return }
                guard conversationId == self.conversationId else { return }
                self.typingHandler?.handleMatrixTypingIndicator(userIds: userIds)
            }
        }

        #if DEBUG
        print("[ChatViewModel] Matrix message handler setup complete")
        #endif
    }

    // MARK: - Load More Messages

    func loadMoreMessages() async {
        guard !isLoadingHistory, hasMoreMessages else { return }

        isLoadingHistory = true
        let previousCount = messages.count

        do {
            let desiredLimit = messages.count + 50
            let matrixMessages = try await matrixBridge.getMessages(conversationId: conversationId, limit: desiredLimit)
            let sorted = matrixMessages.sorted { $0.timestamp < $1.timestamp }

            messages = sorted.map { matrixMessage in
                let novaMessage = matrixBridge.convertToNovaMessage(matrixMessage, conversationId: conversationId)
                return ChatMessage(from: novaMessage, currentUserId: currentUserId)
            }

            hasMoreMessages = messages.count > previousCount && matrixMessages.count >= desiredLimit

            #if DEBUG
            print("[ChatViewModel] Loaded more messages: \(previousCount) -> \(messages.count), hasMore: \(hasMoreMessages)")
            #endif
        } catch {
            #if DEBUG
            print("[ChatViewModel] Load more error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }

    // MARK: - Send Messages

    func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        messageText = ""
        showAttachmentOptions = false

        Task {
            await messageSender?.sendTextMessage(trimmedText)
        }
    }

    func sendImageMessage(image: UIImage) {
        showAttachmentOptions = false

        Task {
            await messageSender?.sendImageMessage(image)
        }
    }

    func sendLocationMessage(location: CLLocationCoordinate2D) {
        showAttachmentOptions = false

        Task {
            await messageSender?.sendLocationMessage(location)
        }
    }

    func sendVoiceMessage(audioData: Data, duration: TimeInterval, url: URL) {
        showAttachmentOptions = false

        Task {
            await messageSender?.sendVoiceMessage(audioData: audioData, duration: duration, url: url)
            audioRecorder.cleanupTempFiles()
        }
    }

    // MARK: - Message Actions

    func handleMessageLongPress(_ message: ChatMessage) {
        Task {
            do {
                try await matrixBridge.deleteMessage(
                    conversationId: conversationId,
                    messageId: message.id,
                    reason: nil
                )
                messages.removeAll { $0.id == message.id }
                #if DEBUG
                print("[ChatViewModel] Message deleted: \(message.id)")
                #endif
            } catch {
                #if DEBUG
                print("[ChatViewModel] Failed to delete message: \(error)")
                #endif
                self.error = "無法刪除消息"
            }
        }
    }

    func retryFailedMessage(_ message: ChatMessage) {
        guard message.status == .failed else { return }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }

        messages[index].status = .sending

        let messageId = message.id
        let messageText = message.text

        Task {
            do {
                let eventId = try await withTimeout(seconds: 30) {
                    try await self.matrixBridge.sendMessage(conversationId: self.conversationId, content: messageText)
                }

                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].id = eventId
                    messages[idx].status = .sent
                }

                #if DEBUG
                print("[ChatViewModel] ✅ Message retry succeeded: \(eventId)")
                #endif
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].status = .failed
                }
                self.error = getMessageSendErrorMessage(for: error)

                #if DEBUG
                print("[ChatViewModel] ❌ Message retry failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Photo/Camera Handling

    func handlePhotoSelection(_ newItem: PhotosPickerItem?) {
        Task {
            do {
                if let data = try await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    sendImageMessage(image: image)
                }
            } catch {
                print("Failed to load photo: \(error.localizedDescription)")
            }
        }
    }

    func handleCameraImage(_ newImage: UIImage?) {
        if let image = newImage {
            sendImageMessage(image: image)
            cameraImage = nil
        }
    }

    func handleLocationUpdate(_ newLocation: CLLocationCoordinate2D?) {
        if let location = newLocation, showLocationAlert {
            sendLocationMessage(location: location)
            showLocationAlert = false
        }
    }

    func checkCameraPermissionAndOpen() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showCamera = true
                    } else {
                        self.showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
    }

    // MARK: - Voice Recording

    func startVoiceRecording() {
        Task {
            let started = await audioRecorder.startRecording()
            if started {
                isRecordingVoice = true
                #if DEBUG
                print("[ChatViewModel] Voice recording started")
                #endif
            } else {
                if !audioRecorder.permissionGranted {
                    showMicrophonePermissionAlert = true
                } else if let errorMsg = audioRecorder.errorMessage {
                    error = errorMsg
                }
            }
        }
    }

    func cancelVoiceRecording() {
        audioRecorder.cancelRecording()
        isRecordingVoice = false
        #if DEBUG
        print("[ChatViewModel] Voice recording cancelled")
        #endif
    }

    func stopAndSendVoiceMessage() {
        guard let result = audioRecorder.stopRecording() else {
            isRecordingVoice = false
            error = "Failed to save recording"
            return
        }

        isRecordingVoice = false

        guard result.duration >= 1.0 else {
            #if DEBUG
            print("[ChatViewModel] Recording too short: \(result.duration)s")
            #endif
            error = "Recording too short"
            audioRecorder.cleanupTempFiles()
            return
        }

        sendVoiceMessage(audioData: result.data, duration: result.duration, url: result.url)
    }

    func handleVoiceRecordDragChanged(_ value: DragGesture.Value) {
        voiceRecordDragOffset = value.translation.height
    }

    func handleVoiceRecordDragEnded(_ value: DragGesture.Value) {
        if voiceRecordDragOffset < voiceCancelThreshold {
            cancelVoiceRecording()
        } else if isRecordingVoice {
            stopAndSendVoiceMessage()
        }
        voiceRecordDragOffset = 0
    }

    // MARK: - File Handling

    func handleDocumentPicked(data: Data, filename: String, mimeType: String) {
        Task {
            isUploadingFile = true
            isSending = true

            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent(filename)
                try data.write(to: tempFileURL)

                #if DEBUG
                print("[ChatViewModel] 📎 Sending file: \(filename) (\(data.count) bytes)")
                #endif

                let eventId = try await MatrixBridgeService.shared.sendMessage(
                    conversationId: conversationId,
                    content: filename,
                    mediaURL: tempFileURL,
                    mimeType: mimeType
                )

                try? FileManager.default.removeItem(at: tempFileURL)

                #if DEBUG
                print("[ChatViewModel] ✅ File sent via Matrix: \(eventId)")
                #endif
            } catch {
                #if DEBUG
                print("[ChatViewModel] ❌ Failed to send file: \(error)")
                #endif
                self.error = getFileSendErrorMessage(for: error, filename: filename)
            }

            isUploadingFile = false
            isSending = false
        }
    }

    // MARK: - Typing Indicator

    func sendTypingIndicator(isTyping: Bool) {
        if isTyping {
            typingHandler?.sendTypingStart()
        } else {
            typingHandler?.sendTypingStop()
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        MatrixBridgeService.shared.onMatrixMessage = nil
        MatrixBridgeService.shared.onTypingIndicator = nil
        matrixMessageHandlerSetup = false

        Task {
            await matrixBridge.stopListening(conversationId: conversationId)
            try? await matrixBridge.setTyping(conversationId: conversationId, isTyping: false)
        }

        typingHandler?.cleanup()

        #if DEBUG
        print("[ChatViewModel] Cleanup completed for conversation \(conversationId)")
        #endif
    }

    // MARK: - Helper Methods

    func currentDateString() -> String {
        Self.dateFormatter.string(from: Date())
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Error Message Helpers

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MessageSendError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func getMessageSendErrorMessage(for error: Error) -> String {
        if let sendError = error as? MessageSendError {
            switch sendError {
            case .timeout:
                return "Message sending timed out. Tap to retry."
            }
        }

        if let matrixError = error as? MatrixBridgeError {
            switch matrixError {
            case .notInitialized:
                return "Connection not ready. Tap to retry."
            case .notAuthenticated:
                return "Please sign in again."
            case .sessionExpired:
                return "Session expired. Please restart the app."
            case .roomMappingFailed:
                return "Chat room not found."
            case .messageSendFailed(let reason):
                return "Failed to send: \(reason)"
            case .bridgeDisabled:
                return "Messaging is temporarily unavailable."
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Tap to retry."
            case NSURLErrorTimedOut:
                return "Request timed out. Tap to retry."
            default:
                return "Network error. Tap to retry."
            }
        }

        return "Failed to send message. Tap to retry."
    }

    func getImageSendErrorMessage(for error: Error) -> String {
        if let matrixError = error as? MatrixBridgeError {
            switch matrixError {
            case .notInitialized:
                return "Connection not ready. Please try again."
            case .notAuthenticated:
                return "Please sign in again to send images."
            case .sessionExpired:
                return "Session expired. Please restart the app."
            case .roomMappingFailed:
                return "Chat room not found. Please reopen the chat."
            case .messageSendFailed(let reason):
                return "Failed to send: \(reason)"
            case .bridgeDisabled:
                return "Messaging is temporarily unavailable."
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Please check your network."
            case NSURLErrorTimedOut:
                return "Request timed out. Please try again."
            case NSURLErrorNetworkConnectionLost:
                return "Connection lost. Please try again."
            case NSURLErrorCannotConnectToHost:
                return "Cannot connect to server. Please try later."
            default:
                return "Network error. Please check your connection."
            }
        }

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "Image file not found. Please try selecting again."
            case NSFileReadNoPermissionError:
                return "Cannot access image. Please check permissions."
            case NSFileWriteOutOfSpaceError:
                return "Storage full. Please free up space."
            default:
                break
            }
        }

        let description = error.localizedDescription
        if description.isEmpty || description == "The operation couldn't be completed." {
            return "Failed to send image. Please try again."
        }
        return "Failed to send image: \(description)"
    }

    private func getFileSendErrorMessage(for error: Error, filename: String) -> String {
        if let matrixError = error as? MatrixBridgeError {
            switch matrixError {
            case .notInitialized:
                return "Connection not ready. Please try again."
            case .notAuthenticated:
                return "Please sign in again to send files."
            case .sessionExpired:
                return "Session expired. Please restart the app."
            case .roomMappingFailed:
                return "Chat room not found. Please reopen the chat."
            case .messageSendFailed(let reason):
                return "Failed to send \(filename): \(reason)"
            case .bridgeDisabled:
                return "Messaging is temporarily unavailable."
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Please check your network."
            case NSURLErrorTimedOut:
                return "Upload timed out. Please try again."
            case NSURLErrorNetworkConnectionLost:
                return "Connection lost during upload. Please try again."
            default:
                return "Network error. Please check your connection."
            }
        }

        let description = error.localizedDescription
        if description.isEmpty || description == "The operation couldn't be completed." {
            return "Failed to send \(filename). Please try again."
        }
        return "Failed to send file: \(description)"
    }

    func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt": return "text/plain"
        case "zip": return "application/zip"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}
