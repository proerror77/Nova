import Foundation
import CallKit
import AVFoundation
import Combine
import UIKit

// MARK: - CallKit Manager

/// Manages CallKit integration for native iOS call UI and system integration
@MainActor
final class CallKitManager: NSObject, ObservableObject {
    static let shared = CallKitManager()

    // MARK: - Published Properties

    @Published private(set) var hasActiveCall: Bool = false
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var isOnHold: Bool = false

    // MARK: - Private Properties

    private var provider: CXProvider?
    private let callController = CXCallController()
    private var currentCallUUID: UUID?
    private var currentRoomId: String?
    private var pendingIncomingCall: PendingCall?
    private var cancellables = Set<AnyCancellable>()

    // Callbacks
    private var onCallStarted: ((String, Bool) -> Void)?
    private var onCallEnded: (() -> Void)?
    private var onMuteToggled: ((Bool) -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
        configureProvider()
        configureAudioSession()
    }

    // MARK: - Configuration

    private func configureProvider() {
        // iOS 14+: Use CXProviderConfiguration() - localizedName is derived from app display name
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = true

        // Set app icon for call UI
        if let iconImage = UIImage(named: "AppIcon") {
            configuration.iconTemplateImageData = iconImage.pngData()
        }

        // Ring tone (optional - uses system default if not set)
        // configuration.ringtoneSound = "ringtone.caf"

        provider = CXProvider(configuration: configuration)
        provider?.setDelegate(self, queue: .main)
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
            )
        } catch {
            #if DEBUG
            print("[CallKit] Failed to configure audio session: \(error)")
            #endif
        }
    }

    // MARK: - Public Methods

    /// Set callbacks for call events
    func setCallbacks(
        onCallStarted: @escaping (String, Bool) -> Void,
        onCallEnded: @escaping () -> Void,
        onMuteToggled: @escaping (Bool) -> Void
    ) {
        self.onCallStarted = onCallStarted
        self.onCallEnded = onCallEnded
        self.onMuteToggled = onMuteToggled
    }

    /// Report an incoming call to the system
    /// - Parameters:
    ///   - roomId: The Matrix room ID
    ///   - callerName: Display name of the caller
    ///   - hasVideo: Whether the call has video
    func reportIncomingCall(
        roomId: String,
        callerName: String,
        hasVideo: Bool = false
    ) async throws {
        let uuid = UUID()

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: roomId)
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = true
        update.supportsDTMF = false

        // Store pending call info
        pendingIncomingCall = PendingCall(
            uuid: uuid,
            roomId: roomId,
            callerName: callerName,
            hasVideo: hasVideo
        )

        return try await withCheckedThrowingContinuation { continuation in
            provider?.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
                if let error = error {
                    #if DEBUG
                    print("[CallKit] Failed to report incoming call: \(error)")
                    #endif
                    Task { @MainActor in
                        self?.pendingIncomingCall = nil
                    }
                    continuation.resume(throwing: error)
                } else {
                    #if DEBUG
                    print("[CallKit] Reported incoming call from: \(callerName)")
                    #endif
                    continuation.resume()
                }
            }
        }
    }

    /// Start an outgoing call
    /// - Parameters:
    ///   - roomId: The Matrix room ID
    ///   - roomName: Display name for the call
    ///   - hasVideo: Whether to start with video
    func startOutgoingCall(
        roomId: String,
        roomName: String,
        hasVideo: Bool = false
    ) async throws {
        let uuid = UUID()
        currentCallUUID = uuid
        currentRoomId = roomId

        let handle = CXHandle(type: .generic, value: roomId)
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        startCallAction.isVideo = hasVideo
        startCallAction.contactIdentifier = roomName

        let transaction = CXTransaction(action: startCallAction)

        try await callController.request(transaction)

        hasActiveCall = true

        #if DEBUG
        print("[CallKit] Started outgoing call to: \(roomName)")
        #endif
    }

    /// Report that an outgoing call has connected
    func reportOutgoingCallConnected() {
        guard let uuid = currentCallUUID else { return }

        provider?.reportOutgoingCall(with: uuid, connectedAt: Date())

        #if DEBUG
        print("[CallKit] Outgoing call connected")
        #endif
    }

    /// Report that an outgoing call started connecting
    func reportOutgoingCallStartedConnecting() {
        guard let uuid = currentCallUUID else { return }

        provider?.reportOutgoingCall(with: uuid, startedConnectingAt: Date())

        #if DEBUG
        print("[CallKit] Outgoing call started connecting")
        #endif
    }

    /// End the current call
    func endCall() async throws {
        guard let uuid = currentCallUUID else {
            #if DEBUG
            print("[CallKit] No active call to end")
            #endif
            return
        }

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        try await callController.request(transaction)

        #if DEBUG
        print("[CallKit] End call requested")
        #endif
    }

    /// Report that the call ended (for incoming calls that end remotely)
    func reportCallEnded(reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = currentCallUUID else { return }

        provider?.reportCall(with: uuid, endedAt: Date(), reason: reason)
        cleanupCall()

        #if DEBUG
        print("[CallKit] Call ended with reason: \(reason.rawValue)")
        #endif
    }

    /// Toggle mute state
    func toggleMute() async throws {
        guard let uuid = currentCallUUID else { return }

        let newMuteState = !isMuted
        let muteAction = CXSetMutedCallAction(call: uuid, muted: newMuteState)
        let transaction = CXTransaction(action: muteAction)

        try await callController.request(transaction)
    }

    /// Toggle hold state
    func toggleHold() async throws {
        guard let uuid = currentCallUUID else { return }

        let newHoldState = !isOnHold
        let holdAction = CXSetHeldCallAction(call: uuid, onHold: newHoldState)
        let transaction = CXTransaction(action: holdAction)

        try await callController.request(transaction)
    }

    /// Update call info (e.g., when caller name becomes available)
    func updateCall(callerName: String? = nil, hasVideo: Bool? = nil) {
        guard let uuid = currentCallUUID else { return }

        let update = CXCallUpdate()
        if let name = callerName {
            update.localizedCallerName = name
        }
        if let video = hasVideo {
            update.hasVideo = video
        }

        provider?.reportCall(with: uuid, updated: update)
    }

    // MARK: - Private Methods

    private func cleanupCall() {
        currentCallUUID = nil
        currentRoomId = nil
        pendingIncomingCall = nil
        hasActiveCall = false
        isMuted = false
        isOnHold = false
    }

    private func activateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
            #if DEBUG
            print("[CallKit] Audio session activated")
            #endif
        } catch {
            #if DEBUG
            print("[CallKit] Failed to activate audio session: \(error)")
            #endif
        }
    }

    private func deactivateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            #if DEBUG
            print("[CallKit] Audio session deactivated")
            #endif
        } catch {
            #if DEBUG
            print("[CallKit] Failed to deactivate audio session: \(error)")
            #endif
        }
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {

    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Provider did reset")
            #endif
            cleanupCall()
            onCallEnded?()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Start call action")
            #endif

            // Configure audio session
            activateAudioSession()

            // Report connecting
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

            // Notify that call should start
            let roomId = action.handle.value
            onCallStarted?(roomId, action.isVideo)

            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Answer call action")
            #endif

            // Configure audio session
            activateAudioSession()

            // Get pending call info
            if let pendingCall = pendingIncomingCall {
                currentCallUUID = pendingCall.uuid
                currentRoomId = pendingCall.roomId
                hasActiveCall = true

                // Notify that call should be answered
                onCallStarted?(pendingCall.roomId, pendingCall.hasVideo)
            }

            pendingIncomingCall = nil
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] End call action")
            #endif

            // Notify that call ended
            onCallEnded?()

            cleanupCall()
            deactivateAudioSession()

            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Set muted action: \(action.isMuted)")
            #endif

            isMuted = action.isMuted
            onMuteToggled?(action.isMuted)

            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Set held action: \(action.isOnHold)")
            #endif

            isOnHold = action.isOnHold

            // Pause/resume audio based on hold state
            if action.isOnHold {
                // Call is on hold - could pause media here
            } else {
                // Call resumed
            }

            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Audio session activated by system")
            #endif
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Audio session deactivated by system")
            #endif
        }
    }

    nonisolated func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        Task { @MainActor in
            #if DEBUG
            print("[CallKit] Action timed out: \(type(of: action))")
            #endif
            action.fail()
        }
    }
}

// MARK: - Pending Call

/// Represents a pending incoming call before it's answered
private struct PendingCall {
    let uuid: UUID
    let roomId: String
    let callerName: String
    let hasVideo: Bool
}

// MARK: - CallKit Error

enum CallKitError: LocalizedError {
    case noActiveCall
    case callAlreadyExists
    case systemError(Error)

    var errorDescription: String? {
        switch self {
        case .noActiveCall:
            return "No active call"
        case .callAlreadyExists:
            return "A call is already in progress"
        case .systemError(let error):
            return "System error: \(error.localizedDescription)"
        }
    }
}
