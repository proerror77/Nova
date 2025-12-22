import Foundation
import Combine
import UserNotifications

// MARK: - Call Coordinator

/// Coordinates between ElementCallService, CallKitManager, and the UI
/// Handles call lifecycle, notifications, and state synchronization
@MainActor
final class CallCoordinator: ObservableObject {
    static let shared = CallCoordinator()

    // MARK: - Published Properties

    @Published private(set) var currentCall: CurrentCallInfo?
    @Published private(set) var incomingCallInfo: IncomingCallInfo?
    @Published var showCallView: Bool = false
    @Published var showIncomingCallAlert: Bool = false

    // MARK: - Services

    private let elementCallService = ElementCallService.shared
    private let callKitManager = CallKitManager.shared

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupBindings()
        setupCallKitCallbacks()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Sync with ElementCallService
        elementCallService.$isInCall
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isInCall in
                if !isInCall {
                    self?.currentCall = nil
                }
            }
            .store(in: &cancellables)

        elementCallService.$callState
            .receive(on: DispatchQueue.main)
            .sink { state in
                switch state {
                case .connected:
                    CallKitManager.shared.reportOutgoingCallConnected()
                case .failed(let error):
                    #if DEBUG
                    print("[CallCoordinator] Call failed: \(error)")
                    #endif
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func setupCallKitCallbacks() {
        callKitManager.setCallbacks(
            onCallStarted: { [weak self] roomId, hasVideo in
                Task { @MainActor in
                    await self?.handleCallStarted(roomId: roomId, hasVideo: hasVideo)
                }
            },
            onCallEnded: { [weak self] in
                Task { @MainActor in
                    await self?.handleCallEnded()
                }
            },
            onMuteToggled: { [weak self] isMuted in
                Task { @MainActor in
                    self?.handleMuteToggled(isMuted: isMuted)
                }
            }
        )
    }

    // MARK: - Public Methods - Starting Calls

    /// Start a new call in a room
    /// - Parameters:
    ///   - roomId: The Matrix room ID
    ///   - roomName: Display name for the room/call
    ///   - isVideoCall: Whether to start with video enabled
    func startCall(
        roomId: String,
        roomName: String,
        isVideoCall: Bool
    ) async throws {
        // Check feature flags
        if isVideoCall && !FeatureFlags.shared.enableVideoCalls {
            throw CallError.permissionDenied
        }
        if !isVideoCall && !FeatureFlags.shared.enableVoiceCalls {
            throw CallError.permissionDenied
        }

        // Check if already in a call
        guard currentCall == nil else {
            throw CallError.alreadyInCall
        }

        #if DEBUG
        print("[CallCoordinator] Starting call in room: \(roomId)")
        #endif

        // Report to CallKit
        try await callKitManager.startOutgoingCall(
            roomId: roomId,
            roomName: roomName,
            hasVideo: isVideoCall
        )

        // Store current call info
        currentCall = CurrentCallInfo(
            roomId: roomId,
            roomName: roomName,
            isVideoCall: isVideoCall,
            isOutgoing: true
        )

        // Start the actual Element Call
        let config = try await elementCallService.startCall(
            in: roomId,
            intent: .startCall,
            videoEnabled: isVideoCall
        )

        // Update with actual call URL
        currentCall?.callURL = config.url

        // Show call UI
        showCallView = true

        #if DEBUG
        print("[CallCoordinator] Call started successfully")
        #endif
    }

    /// Start a DM call
    func startDMCall(
        roomId: String,
        recipientName: String,
        isVideoCall: Bool
    ) async throws {
        guard currentCall == nil else {
            throw CallError.alreadyInCall
        }

        #if DEBUG
        print("[CallCoordinator] Starting DM call to: \(recipientName)")
        #endif

        // Report to CallKit
        try await callKitManager.startOutgoingCall(
            roomId: roomId,
            roomName: recipientName,
            hasVideo: isVideoCall
        )

        // Store current call info
        currentCall = CurrentCallInfo(
            roomId: roomId,
            roomName: recipientName,
            isVideoCall: isVideoCall,
            isOutgoing: true
        )

        // Start the actual Element Call with DM intent
        let config = try await elementCallService.startCall(
            in: roomId,
            intent: .startCallDM,
            videoEnabled: isVideoCall
        )

        currentCall?.callURL = config.url
        showCallView = true
    }

    /// Join an existing call in a room
    func joinCall(
        roomId: String,
        roomName: String,
        isVideoCall: Bool = true
    ) async throws {
        guard currentCall == nil else {
            throw CallError.alreadyInCall
        }

        #if DEBUG
        print("[CallCoordinator] Joining call in room: \(roomId)")
        #endif

        // Report to CallKit
        try await callKitManager.startOutgoingCall(
            roomId: roomId,
            roomName: roomName,
            hasVideo: isVideoCall
        )

        // Store current call info
        currentCall = CurrentCallInfo(
            roomId: roomId,
            roomName: roomName,
            isVideoCall: isVideoCall,
            isOutgoing: true
        )

        // Join the Element Call
        let config = try await elementCallService.joinCall(
            in: roomId,
            videoEnabled: isVideoCall
        )

        currentCall?.callURL = config.url
        showCallView = true
    }

    // MARK: - Public Methods - Incoming Calls

    /// Handle an incoming call notification
    func handleIncomingCall(
        roomId: String,
        callerName: String,
        callerUserId: String,
        hasVideo: Bool
    ) async {
        #if DEBUG
        print("[CallCoordinator] Incoming call from: \(callerName)")
        #endif

        // Store incoming call info
        incomingCallInfo = IncomingCallInfo(
            roomId: roomId,
            callerName: callerName,
            callerUserId: callerUserId,
            hasVideo: hasVideo
        )

        do {
            // Report to CallKit for native call UI
            try await callKitManager.reportIncomingCall(
                roomId: roomId,
                callerName: callerName,
                hasVideo: hasVideo
            )
        } catch {
            #if DEBUG
            print("[CallCoordinator] Failed to report incoming call: \(error)")
            #endif

            // Fall back to in-app notification if CallKit fails
            showIncomingCallAlert = true
        }
    }

    /// Accept an incoming call (called when user answers via CallKit or in-app UI)
    func acceptIncomingCall() async throws {
        guard let incoming = incomingCallInfo else {
            throw CallError.roomNotFound
        }

        #if DEBUG
        print("[CallCoordinator] Accepting call from: \(incoming.callerName)")
        #endif

        // Create current call info
        currentCall = CurrentCallInfo(
            roomId: incoming.roomId,
            roomName: incoming.callerName,
            isVideoCall: incoming.hasVideo,
            isOutgoing: false
        )

        // Join the call
        let config = try await elementCallService.startCall(
            in: incoming.roomId,
            intent: .joinExisting,
            videoEnabled: incoming.hasVideo
        )

        currentCall?.callURL = config.url
        incomingCallInfo = nil
        showIncomingCallAlert = false
        showCallView = true
    }

    /// Decline an incoming call
    func declineIncomingCall() async {
        guard incomingCallInfo != nil else { return }

        #if DEBUG
        print("[CallCoordinator] Declining incoming call")
        #endif

        // Report call ended to CallKit
        callKitManager.reportCallEnded(reason: .declinedElsewhere)

        incomingCallInfo = nil
        showIncomingCallAlert = false
    }

    // MARK: - Public Methods - During Call

    /// End the current call
    func endCall() async {
        guard currentCall != nil else { return }

        #if DEBUG
        print("[CallCoordinator] Ending call")
        #endif

        // End via CallKit
        do {
            try await callKitManager.endCall()
        } catch {
            #if DEBUG
            print("[CallCoordinator] Failed to end call via CallKit: \(error)")
            #endif
        }

        // End the Element Call
        await elementCallService.endCall()

        // Cleanup
        currentCall = nil
        showCallView = false
    }

    /// Toggle video during call
    func toggleVideo() {
        elementCallService.toggleVideo()
    }

    /// Toggle mute during call
    func toggleMute() async {
        do {
            try await callKitManager.toggleMute()
        } catch {
            // Fallback to direct toggle
            elementCallService.toggleMute()
        }
    }

    /// Toggle speaker
    func toggleSpeaker() {
        // Handle speaker toggle via AVAudioSession
        // This is managed separately from CallKit
    }

    // MARK: - Public Methods - Utility

    /// Check if there's an active call in a specific room
    func hasActiveCall(in roomId: String) -> Bool {
        return currentCall?.roomId == roomId
    }

    /// Get call info for a room
    func getCallInfo(for roomId: String) -> CurrentCallInfo? {
        guard currentCall?.roomId == roomId else { return nil }
        return currentCall
    }

    // MARK: - Private Methods - CallKit Callbacks

    private func handleCallStarted(roomId: String, hasVideo: Bool) async {
        // If this is an incoming call being answered
        if incomingCallInfo != nil {
            do {
                try await acceptIncomingCall()
            } catch {
                #if DEBUG
                print("[CallCoordinator] Failed to accept call: \(error)")
                #endif
            }
        }
        // For outgoing calls, this is handled by startCall()
    }

    private func handleCallEnded() async {
        // End the Element Call
        await elementCallService.endCall()

        // Cleanup
        currentCall = nil
        incomingCallInfo = nil
        showCallView = false
        showIncomingCallAlert = false
    }

    private func handleMuteToggled(isMuted: Bool) {
        // Sync with Element Call
        if let activeCall = elementCallService.activeCall {
            if activeCall.audioMuted != isMuted {
                elementCallService.toggleMute()
            }
        }
    }
}

// MARK: - Current Call Info

/// Information about the current active call
struct CurrentCallInfo: Identifiable {
    let id = UUID()
    let roomId: String
    let roomName: String
    let isVideoCall: Bool
    let isOutgoing: Bool
    var callURL: URL?
    let startTime = Date()

    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

// MARK: - Incoming Call Info

/// Information about an incoming call
struct IncomingCallInfo: Identifiable {
    let id = UUID()
    let roomId: String
    let callerName: String
    let callerUserId: String
    let hasVideo: Bool
    let receivedAt = Date()
}

// MARK: - Push Notification Handler Extension

extension CallCoordinator {

    /// Handle a VoIP push notification
    func handleVoIPPush(payload: [AnyHashable: Any]) async {
        #if DEBUG
        print("[CallCoordinator] Received VoIP push: \(payload)")
        #endif

        // Parse the push payload
        guard let roomId = payload["room_id"] as? String,
              let senderUserId = payload["sender_user_id"] as? String else {
            #if DEBUG
            print("[CallCoordinator] Invalid VoIP push payload")
            #endif
            return
        }

        let callerName = payload["sender_display_name"] as? String ?? senderUserId
        let hasVideo = (payload["has_video"] as? Bool) ?? false

        // Handle the incoming call
        await handleIncomingCall(
            roomId: roomId,
            callerName: callerName,
            callerUserId: senderUserId,
            hasVideo: hasVideo
        )
    }

    /// Handle a call notification from Matrix sync
    func handleMatrixCallNotification(
        roomId: String,
        eventId: String,
        callType: String,
        senderUserId: String,
        senderDisplayName: String?
    ) async {
        #if DEBUG
        print("[CallCoordinator] Matrix call notification: \(callType) from \(senderUserId)")
        #endif

        let hasVideo = callType.lowercased().contains("video")
        let callerName = senderDisplayName ?? senderUserId

        await handleIncomingCall(
            roomId: roomId,
            callerName: callerName,
            callerUserId: senderUserId,
            hasVideo: hasVideo
        )
    }
}
