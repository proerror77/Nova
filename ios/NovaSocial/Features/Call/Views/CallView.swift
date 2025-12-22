import SwiftUI
import WebKit
import AVFoundation

// MARK: - Call View

/// Full-screen view for Element Call video/audio calls
struct CallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var callService = ElementCallService.shared

    // MARK: - Properties

    let roomId: String
    let roomName: String
    let isVideoCall: Bool
    let intent: CallIntent

    // MARK: - State

    @State private var callURL: URL?
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showControls = true
    @State private var callDuration: TimeInterval = 0
    @State private var durationTimer: Timer?

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Main content
            if let url = callURL {
                // WebView for Element Call
                ElementCallWebView(
                    url: url,
                    onCallEnded: handleCallEnded,
                    onError: handleWebViewError
                )
                .ignoresSafeArea()
            } else if isLoading {
                // Loading state
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)

                    Text("Connecting...")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(roomName)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            // Overlay controls
            if showControls {
                controlsOverlay
            }
        }
        .onAppear {
            startCall()
        }
        .onDisappear {
            durationTimer?.invalidate()
        }
        .alert("Call Error", isPresented: $showError) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .statusBar(hidden: true)
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }

                Spacer()

                VStack(spacing: 4) {
                    Text(roomName)
                        .font(.headline)
                        .foregroundColor(.white)

                    if callDuration > 0 {
                        Text(formatDuration(callDuration))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                // Placeholder for symmetry
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            // Bottom controls
            HStack(spacing: 32) {
                // Mute button
                CallControlButton(
                    systemImage: callService.activeCall?.audioMuted == true ? "mic.slash.fill" : "mic.fill",
                    isActive: callService.activeCall?.audioMuted != true,
                    action: {
                        callService.toggleMute()
                    }
                )

                // End call button
                Button(action: endCall) {
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Color.red)
                        .clipShape(Circle())
                }

                // Video toggle button
                CallControlButton(
                    systemImage: callService.activeCall?.videoEnabled == true ? "video.fill" : "video.slash.fill",
                    isActive: callService.activeCall?.videoEnabled == true,
                    action: {
                        callService.toggleVideo()
                    }
                )
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Actions

    private func startCall() {
        Task {
            do {
                // Request microphone and camera permissions
                let audioGranted = await requestMicrophonePermission()
                let videoGranted = isVideoCall ? await requestCameraPermission() : true

                guard audioGranted else {
                    showError(message: "Microphone permission is required for calls")
                    return
                }

                if isVideoCall && !videoGranted {
                    showError(message: "Camera permission is required for video calls")
                    return
                }

                // Start the call
                let config = try await callService.startCall(
                    in: roomId,
                    intent: intent,
                    videoEnabled: isVideoCall
                )

                await MainActor.run {
                    self.callURL = config.url
                    self.isLoading = false
                    startDurationTimer()
                }

            } catch {
                await MainActor.run {
                    showError(message: error.localizedDescription)
                }
            }
        }
    }

    private func endCall() {
        Task {
            await callService.endCall()
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func handleCallEnded() {
        Task {
            await callService.endCall()
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func handleWebViewError(_ error: Error) {
        showError(message: error.localizedDescription)
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
        isLoading = false
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak callService] _ in
            Task { @MainActor in
                if let startTime = callService?.activeCall?.startTime {
                    self.callDuration = Date().timeIntervalSince(startTime)
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - Call Control Button

struct CallControlButton: View {
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.white)
                .padding(16)
                .background(isActive ? Color.gray.opacity(0.3) : Color.red.opacity(0.8))
                .clipShape(Circle())
        }
    }
}

// MARK: - Element Call WebView

/// WebView wrapper for Element Call
struct ElementCallWebView: UIViewRepresentable {
    let url: URL
    let onCallEnded: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Enable inline media playback
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = true

        // Enable JavaScript
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // User content controller for widget API communication
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "elementCallHandler")
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false

        // Allow camera and microphone
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Load Element Call URL
        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: ElementCallWebView

        init(_ parent: ElementCallWebView) {
            self.parent = parent
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            #if DEBUG
            print("[ElementCall] WebView loaded successfully")
            #endif

            // Inject JavaScript to listen for call events
            let script = """
            window.addEventListener('message', function(event) {
                if (event.data && event.data.api === 'fromWidget') {
                    window.webkit.messageHandlers.elementCallHandler.postMessage(event.data);
                }
            });
            """
            webView.evaluateJavaScript(script)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("[ElementCall] WebView navigation failed: \(error)")
            #endif
            parent.onError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("[ElementCall] WebView provisional navigation failed: \(error)")
            #endif
            parent.onError(error)
        }

        // MARK: - WKUIDelegate

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            // Grant media permissions for Element Call
            decisionHandler(.grant)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            #if DEBUG
            print("[ElementCall] JS Alert: \(message)")
            #endif
            completionHandler()
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }

            #if DEBUG
            print("[ElementCall] Received message: \(body)")
            #endif

            // Handle widget API messages
            if let action = body["action"] as? String {
                switch action {
                case "io.element.hangup", "hangup":
                    parent.onCallEnded()
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CallView(
        roomId: "!test:matrix.org",
        roomName: "Test Call",
        isVideoCall: true,
        intent: .startCall
    )
}
