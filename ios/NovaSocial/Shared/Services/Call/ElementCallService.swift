import Foundation
import MatrixRustSDK
import Combine

// MARK: - Element Call Service

/// Service for managing Element Call (WebRTC-based video/audio calls)
/// Uses Matrix Widget API to embed Element Call in a WebView
@MainActor
final class ElementCallService: ObservableObject {
    static let shared = ElementCallService()

    // MARK: - Published Properties

    @Published private(set) var activeCall: ActiveCall?
    @Published private(set) var callState: CallState = .idle
    @Published private(set) var isInCall: Bool = false

    // MARK: - Configuration

    /// Element Call URL (configurable per environment)
    var elementCallURL: String {
        switch APIConfig.current {
        case .development, .staging:
            return "https://call.element.dev"
        case .production:
            return "https://call.element.io"
        }
    }

    // MARK: - Private Properties

    private var widgetDriver: WidgetDriver?
    private var widgetDriverHandle: WidgetDriverHandle?
    private var callDeclineTask: TaskHandle?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Start a call in a room
    /// - Parameters:
    ///   - roomId: The Matrix room ID
    ///   - intent: Call intent (start new call, join existing, DM call)
    ///   - videoEnabled: Whether to start with video enabled
    /// - Returns: Call configuration for the WebView
    func startCall(
        in roomId: String,
        intent: CallIntent = .startCall,
        videoEnabled: Bool = true
    ) async throws -> ElementCallConfiguration {
        guard callState == .idle else {
            throw CallError.alreadyInCall
        }

        callState = .connecting

        do {
            // Get user info for widget
            guard let userId = MatrixService.shared.userId else {
                throw CallError.notLoggedIn
            }
            let deviceId = MatrixService.shared.currentDeviceId

            // Generate unique widget ID
            let widgetId = "nova-call-\(UUID().uuidString.prefix(8))"

            // Create widget properties
            let properties = VirtualElementCallWidgetProperties(
                elementCallUrl: elementCallURL,
                widgetId: widgetId,
                parentUrl: nil,
                fontScale: 1.0,
                font: nil,
                encryption: .perParticipantKeys,
                posthogUserId: nil,
                posthogApiHost: nil,
                posthogApiKey: nil,
                rageshakeSubmitUrl: nil,
                sentryDsn: nil,
                sentryEnvironment: nil
            )

            // Create widget configuration
            let config = VirtualElementCallWidgetConfig(
                intent: intent.toSDKIntent,
                skipLobby: false,
                header: .appBar,
                hideHeader: false,
                preload: false,
                appPrompt: false,
                confineToRoom: true,
                hideScreensharing: false,
                controlledAudioDevices: true,
                sendNotificationType: .ring
            )

            // Create widget settings
            let widgetSettings = try newVirtualElementCallWidget(
                props: properties,
                config: config
            )

            // Generate the call URL
            let callURL = try generateCallURL(
                widgetSettings: widgetSettings,
                roomId: roomId,
                userId: userId,
                deviceId: deviceId
            )

            // Create widget driver for communication
            let driverAndHandle = try makeWidgetDriver(settings: widgetSettings)
            self.widgetDriver = driverAndHandle.driver
            self.widgetDriverHandle = driverAndHandle.handle

            // Create active call object
            let activeCall = ActiveCall(
                roomId: roomId,
                widgetId: widgetId,
                callURL: callURL,
                intent: intent,
                videoEnabled: videoEnabled,
                startTime: Date()
            )

            self.activeCall = activeCall
            self.isInCall = true
            self.callState = .connected

            #if DEBUG
            print("[ElementCall] Started call in room: \(roomId)")
            print("[ElementCall] Call URL: \(callURL)")
            #endif

            return ElementCallConfiguration(
                url: callURL,
                widgetId: widgetId,
                roomId: roomId
            )

        } catch {
            callState = .idle
            #if DEBUG
            print("[ElementCall] Failed to start call: \(error)")
            #endif
            throw CallError.failedToStart(error)
        }
    }

    /// Join an existing call in a room
    func joinCall(in roomId: String, videoEnabled: Bool = true) async throws -> ElementCallConfiguration {
        return try await startCall(in: roomId, intent: .joinExisting, videoEnabled: videoEnabled)
    }

    /// End the current call
    func endCall() async {
        guard isInCall else { return }

        callState = .disconnecting

        // Cancel any pending tasks
        callDeclineTask?.cancel()

        // Close widget driver
        widgetDriverHandle = nil
        widgetDriver = nil

        activeCall = nil
        isInCall = false
        callState = .idle

        #if DEBUG
        print("[ElementCall] Call ended")
        #endif
    }

    /// Subscribe to call decline events for incoming call notifications
    func subscribeToCallDeclineEvents(
        in room: Room,
        rtcNotificationEventId: String,
        onDecline: @escaping (String) -> Void
    ) throws {
        let listener = DefaultCallDeclineListener(onDecline: onDecline)
        callDeclineTask = try room.subscribeToCallDeclineEvents(
            rtcNotificationEventId: rtcNotificationEventId,
            listener: listener
        )
    }

    /// Toggle video during call
    func toggleVideo() {
        guard var call = activeCall else { return }
        call.videoEnabled.toggle()
        activeCall = call

        // Send message to widget to toggle video
        // This requires postMessage communication with the WebView
    }

    /// Toggle audio mute during call
    func toggleMute() {
        guard var call = activeCall else { return }
        call.audioMuted.toggle()
        activeCall = call

        // Send message to widget to toggle audio
    }

    // MARK: - Private Methods

    /// Generate the full call URL with all parameters
    private func generateCallURL(
        widgetSettings: WidgetSettings,
        roomId: String,
        userId: String,
        deviceId: String
    ) throws -> URL {
        // The rawUrl from widget settings contains the base URL with placeholders
        var urlString = widgetSettings.rawUrl

        // Replace placeholders
        urlString = urlString.replacingOccurrences(of: "$widgetId", with: widgetSettings.widgetId)
        urlString = urlString.replacingOccurrences(of: "$userId", with: userId)
        urlString = urlString.replacingOccurrences(of: "$roomId", with: roomId)
        urlString = urlString.replacingOccurrences(of: "$deviceId", with: deviceId)

        // Add room ID parameter if not present
        if !urlString.contains("roomId=") {
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)roomId=\(roomId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? roomId)"
        }

        guard let url = URL(string: urlString) else {
            throw CallError.invalidCallURL
        }

        return url
    }
}

// MARK: - Call State

enum CallState: Equatable {
    case idle
    case connecting
    case connected
    case disconnecting
    case reconnecting
    case failed(String)
}

// MARK: - Call Intent

enum CallIntent {
    case startCall
    case joinExisting
    case startCallDM
    case joinExistingDM

    var toSDKIntent: Intent {
        switch self {
        case .startCall:
            return .startCall
        case .joinExisting:
            return .joinExisting
        case .startCallDM:
            return .startCallDm
        case .joinExistingDM:
            return .joinExistingDm
        }
    }
}

// MARK: - Active Call

struct ActiveCall {
    let roomId: String
    let widgetId: String
    let callURL: URL
    let intent: CallIntent
    var videoEnabled: Bool
    var audioMuted: Bool = false
    let startTime: Date

    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

// MARK: - Element Call Configuration

/// Configuration returned when starting a call, used to configure the WebView
struct ElementCallConfiguration {
    let url: URL
    let widgetId: String
    let roomId: String
}

// MARK: - Call Error

enum CallError: LocalizedError {
    case alreadyInCall
    case notLoggedIn
    case failedToStart(Error)
    case invalidCallURL
    case roomNotFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .alreadyInCall:
            return "You are already in a call"
        case .notLoggedIn:
            return "You must be logged in to make calls"
        case .failedToStart(let error):
            return "Failed to start call: \(error.localizedDescription)"
        case .invalidCallURL:
            return "Invalid call URL"
        case .roomNotFound:
            return "Room not found"
        case .permissionDenied:
            return "Permission denied for call"
        }
    }
}

// MARK: - Call Decline Listener

/// Default implementation of CallDeclineListener
final class DefaultCallDeclineListener: CallDeclineListener, @unchecked Sendable {
    private let onDecline: (String) -> Void

    init(onDecline: @escaping (String) -> Void) {
        self.onDecline = onDecline
    }

    func call(declinerUserId: String) {
        #if DEBUG
        print("[ElementCall] Call declined by: \(declinerUserId)")
        #endif
        onDecline(declinerUserId)
    }
}

// MARK: - Widget Capabilities Provider

/// Provides capabilities for the Element Call widget
final class ElementCallCapabilitiesProvider: WidgetCapabilitiesProvider, @unchecked Sendable {
    func acquireCapabilities(capabilities: WidgetCapabilities) -> WidgetCapabilities {
        // Grant all requested capabilities for Element Call
        // In production, you might want to be more selective
        return capabilities
    }
}
