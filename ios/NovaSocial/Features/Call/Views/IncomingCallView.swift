import SwiftUI
import AVFoundation
import AudioToolbox

// MARK: - Incoming Call View

/// Full-screen view for incoming call notifications (in-app fallback)
struct IncomingCallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var callCoordinator = CallCoordinator.shared

    // MARK: - Properties

    let callerName: String
    let callerUserId: String
    let roomId: String
    let hasVideo: Bool

    // MARK: - State

    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var pulseAnimation = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Caller Info
                VStack(spacing: 20) {
                    // Pulsing ring animation
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 2)
                            .frame(width: 140, height: 140)
                            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.5)

                        Circle()
                            .stroke(Color.green.opacity(0.5), lineWidth: 2)
                            .frame(width: 120, height: 120)
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.7)

                        // Avatar placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(callerInitials)
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }

                    // Caller name
                    Text(callerName)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    // Call type
                    HStack(spacing: 8) {
                        Image(systemName: hasVideo ? "video.fill" : "phone.fill")
                        Text(hasVideo ? "Incoming Video Call" : "Incoming Voice Call")
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)
                }

                Spacer()

                // Call actions
                HStack(spacing: 60) {
                    // Decline button
                    VStack(spacing: 8) {
                        Button(action: declineCall) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 70, height: 70)

                                if isDeclining {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "phone.down.fill")
                                        .font(.title)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .disabled(isDeclining || isAccepting)

                        Text("Decline")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // Accept button
                    VStack(spacing: 8) {
                        Button(action: acceptCall) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 70, height: 70)

                                if isAccepting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: hasVideo ? "video.fill" : "phone.fill")
                                        .font(.title)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .disabled(isDeclining || isAccepting)

                        Text("Accept")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            startPulseAnimation()
            playRingtone()
        }
        .onDisappear {
            stopRingtone()
        }
    }

    // MARK: - Computed Properties

    private var callerInitials: String {
        let components = callerName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    // MARK: - Actions

    private func acceptCall() {
        isAccepting = true

        Task {
            do {
                try await callCoordinator.acceptIncomingCall()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                #if DEBUG
                print("[IncomingCall] Failed to accept: \(error)")
                #endif
                await MainActor.run {
                    isAccepting = false
                }
            }
        }
    }

    private func declineCall() {
        isDeclining = true

        Task {
            await callCoordinator.declineIncomingCall()
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            Animation
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: false)
        ) {
            pulseAnimation = true
        }
    }

    // MARK: - Audio

    private func playRingtone() {
        // Play system ringtone or custom sound
        // Note: In production, you might want to use a custom ringtone file
        AudioServicesPlaySystemSound(1005) // System ringtone

        // For custom ringtone:
        // if let url = Bundle.main.url(forResource: "ringtone", withExtension: "caf") {
        //     audioPlayer = try? AVAudioPlayer(contentsOf: url)
        //     audioPlayer?.numberOfLoops = -1
        //     audioPlayer?.play()
        // }
    }

    private func stopRingtone() {
        // Stop ringtone if playing custom sound
        // audioPlayer?.stop()
    }
}

// MARK: - Incoming Call Alert Modifier

/// ViewModifier to show incoming call alert on any view
struct IncomingCallAlertModifier: ViewModifier {
    @ObservedObject private var callCoordinator = CallCoordinator.shared

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $callCoordinator.showIncomingCallAlert) {
                if let incoming = callCoordinator.incomingCallInfo {
                    IncomingCallView(
                        callerName: incoming.callerName,
                        callerUserId: incoming.callerUserId,
                        roomId: incoming.roomId,
                        hasVideo: incoming.hasVideo
                    )
                }
            }
    }
}

extension View {
    /// Add incoming call alert support to a view
    func incomingCallAlert() -> some View {
        modifier(IncomingCallAlertModifier())
    }
}

// MARK: - Preview

#Preview {
    IncomingCallView(
        callerName: "John Doe",
        callerUserId: "@john:matrix.org",
        roomId: "!test:matrix.org",
        hasVideo: true
    )
}
