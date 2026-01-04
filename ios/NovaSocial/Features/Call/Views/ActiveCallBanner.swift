import SwiftUI

// MARK: - Active Call Banner

/// Compact banner shown at the top of the screen during an active call
/// Allows quick return to call view or ending the call
struct ActiveCallBanner: View {
    @ObservedObject private var callCoordinator = CallCoordinator.shared

    // MARK: - State

    @State private var callDuration: TimeInterval = 0
    @State private var durationTimer: Timer?

    // MARK: - Actions

    let onTap: () -> Void

    // MARK: - Body

    var body: some View {
        if let call = callCoordinator.currentCall, !callCoordinator.showCallView {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Call icon with pulse
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 32, height: 32)

                        Image(systemName: call.isVideoCall ? "video.fill" : "phone.fill")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(.white)
                    }

                    // Call info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.roomName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(formatDuration(callDuration))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    // Tap to return indicator
                    Text("Tap to return")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.green)
            }
            .buttonStyle(PlainButtonStyle())
            .onAppear {
                startDurationTimer()
            }
            .onDisappear {
                durationTimer?.invalidate()
                durationTimer = nil
            }
        }
    }

    // MARK: - Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak callCoordinator] _ in
            Task { @MainActor in
                if let call = callCoordinator?.currentCall {
                    callDuration = call.duration
                }
            }
        }
    }

    // MARK: - Formatting

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
}

// MARK: - Active Call Banner Modifier

/// ViewModifier to add active call banner support to any view
struct ActiveCallBannerModifier: ViewModifier {
    @ObservedObject private var callCoordinator = CallCoordinator.shared

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            ActiveCallBanner {
                callCoordinator.showCallView = true
            }

            content
        }
        .fullScreenCover(isPresented: $callCoordinator.showCallView) {
            if let call = callCoordinator.currentCall {
                CallView(
                    roomId: call.roomId,
                    roomName: call.roomName,
                    isVideoCall: call.isVideoCall,
                    intent: call.isOutgoing ? .startCall : .joinExisting
                )
            } else {
                // Fallback: auto-dismiss if call is nil to prevent blank screen
                Color.clear
                    .onAppear {
                        callCoordinator.showCallView = false
                    }
            }
        }
    }
}

extension View {
    /// Add active call banner support to a view
    func activeCallBanner() -> some View {
        modifier(ActiveCallBannerModifier())
    }

    /// Add both incoming call alert and active call banner support
    func callSupport() -> some View {
        self
            .incomingCallAlert()
            .activeCallBanner()
    }
}

// MARK: - Minimized Call View

/// A floating minimized view for the call that can be dragged around
struct MinimizedCallView: View {
    @ObservedObject private var callCoordinator = CallCoordinator.shared

    // MARK: - State

    @State private var position: CGPoint = .zero
    @State private var hasSetInitialPosition = false
    @State private var isDragging = false
    @State private var callDuration: TimeInterval = 0

    // MARK: - Actions

    let onTap: () -> Void

    // MARK: - Body

    var body: some View {
        if let call = callCoordinator.currentCall, !callCoordinator.showCallView {
            GeometryReader { geometry in
                content(for: call, in: geometry)
            }
        }
    }

    @ViewBuilder
    private func content(for call: CurrentCallInfo, in geometry: GeometryProxy) -> some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
                .frame(width: 120, height: 160)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

            VStack(spacing: 8) {
                // Video preview placeholder or avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 80)

                    if call.isVideoCall {
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Image(systemName: "phone.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }

                // Room name
                Text(call.roomName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 100)

                // Duration
                Text(formatDuration(callDuration))
                    .font(.caption2)
                    .foregroundColor(.gray)

                // End call button
                Button(action: endCall) {
                    Image(systemName: "phone.down.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
        }
        .position(position)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    position = value.location
                }
                .onEnded { value in
                    isDragging = false
                    // Snap to edges
                    withAnimation(.spring()) {
                        let screenWidth = geometry.size.width
                        let screenHeight = geometry.size.height
                        var newPosition = value.location

                        // Snap to nearest horizontal edge
                        if value.location.x < screenWidth / 2 {
                            newPosition.x = 70
                        } else {
                            newPosition.x = screenWidth - 70
                        }

                        // Keep within vertical bounds
                        newPosition.y = min(max(100, value.location.y), screenHeight - 200)

                        position = newPosition
                    }
                }
        )
        .onTapGesture {
            onTap()
        }
        .onAppear {
            if !hasSetInitialPosition {
                position = CGPoint(x: geometry.size.width - 80, y: 100)
                hasSetInitialPosition = true
            }
            startDurationTimer()
        }
        .onDisappear {
            durationTimer?.invalidate()
            durationTimer = nil
        }
    }

    // MARK: - Actions

    private func endCall() {
        Task {
            await callCoordinator.endCall()
        }
    }

    // MARK: - Timer

    @State private var durationTimer: Timer?

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak callCoordinator] _ in
            Task { @MainActor in
                if let call = callCoordinator?.currentCall {
                    callDuration = call.duration
                }
            }
        }
    }

    // MARK: - Formatting

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
}

// MARK: - Preview

#Preview("Active Call Banner") {
    VStack {
        // Mock banner
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 32, height: 32)

                Image(systemName: "video.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Team Meeting")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("05:23")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Text("Tap to return")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green)

        Spacer()
    }
}
