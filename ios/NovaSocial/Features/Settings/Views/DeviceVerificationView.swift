import SwiftUI
import MatrixRustSDK

// MARK: - Device Verification View

/// View for managing device verification and cross-signing
struct DeviceVerificationView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var verificationState: VerificationState = .unknown
    @State private var isLoading = false
    @State private var showVerificationFlow = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var verificationData: SessionVerificationData?
    @State private var flowState: VerificationFlowState = .idle
    @State private var pendingRequest: SessionVerificationRequestDetails?

    // MARK: - Delegate

    private var verificationDelegate: DefaultSessionVerificationDelegate?

    // MARK: - Body

    var body: some View {
        List {
            // Status Section
            Section {
                statusRow
            } header: {
                Text("Verification Status")
            } footer: {
                Text("Verify your devices to ensure end-to-end encryption security.")
            }

            // Actions Section
            Section {
                if verificationState != .verified {
                    Button(action: startVerification) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.blue)
                            Text("Verify This Device")
                            Spacer()
                            if isLoading && flowState == .requesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(isLoading)
                }

                if verificationState == .verified {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Device Verified")
                            .foregroundColor(.green)
                    }
                }
            } header: {
                Text("Actions")
            }

            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(
                        icon: "lock.shield",
                        title: "What is Device Verification?",
                        description: "Device verification confirms that you control all your devices and no one else is accessing your account."
                    )

                    Divider()

                    infoRow(
                        icon: "person.2.fill",
                        title: "How it Works",
                        description: "Compare emoji or numbers shown on both devices. If they match, the devices are verified."
                    )

                    Divider()

                    infoRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Why Verify?",
                        description: "Verification prevents man-in-the-middle attacks and ensures your messages stay private."
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Text("About Device Verification")
            }
        }
        .navigationTitle("Device Verification")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshState()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showVerificationFlow) {
            verificationFlowSheet
        }
    }

    // MARK: - Subviews

    private var statusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .foregroundColor(statusColor)
                    .fontWeight(.medium)
            }
        }
    }

    private func infoRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var verificationFlowSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                switch flowState {
                case .idle, .requesting:
                    requestingView

                case .waitingForOther:
                    waitingView

                case .sasStarted:
                    sasStartedView

                case .showingEmojis(let emojis):
                    emojiComparisonView(emojis: emojis)

                case .showingDecimals(let decimals):
                    decimalComparisonView(decimals: decimals)

                case .completed:
                    completedView

                case .cancelled:
                    cancelledView
                }
            }
            .padding()
            .navigationTitle("Verify Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cancelFlow()
                    }
                }
            }
        }
    }

    private var requestingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Starting Verification...")
                .font(.headline)

            Text("Please wait while we set up the verification process.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var waitingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Waiting for Other Device")
                .font(.headline)

            Text("Open your other device and accept the verification request.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if isLoading {
                ProgressView()
            }
        }
    }

    private var sasStartedView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Generating Verification Code...")
                .font(.headline)

            Text("Please wait while we generate the verification code.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func emojiComparisonView(emojis: [SessionVerificationEmoji]) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "face.smiling")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Compare Emoji")
                .font(.title2)
                .fontWeight(.bold)

            Text("Make sure the emoji below appear in the same order on both devices.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Emoji Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(0..<emojis.count, id: \.self) { index in
                    VStack(spacing: 4) {
                        Text(emojis[index].symbol())
                            .font(.system(size: 36))
                        Text(emojis[index].description())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Spacer()

            HStack(spacing: 16) {
                Button(action: declineMatch) {
                    Text("They Don't Match")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                }

                Button(action: approveMatch) {
                    Text("They Match")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .disabled(isLoading)
        }
    }

    private func decimalComparisonView(decimals: [UInt16]) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "number")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text("Compare Numbers")
                .font(.title2)
                .fontWeight(.bold)

            Text("Make sure the numbers below appear in the same order on both devices.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Numbers Display
            HStack(spacing: 20) {
                ForEach(0..<decimals.count, id: \.self) { index in
                    Text("\(decimals[index])")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: declineMatch) {
                    Text("They Don't Match")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                }

                Button(action: approveMatch) {
                    Text("They Match")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .disabled(isLoading)
        }
    }

    private var completedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Verification Complete!")
                .font(.title2)
                .fontWeight(.bold)

            Text("Your device has been successfully verified. Your messages are now secure.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(action: { showVerificationFlow = false }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }

    private var cancelledView: some View {
        VStack(spacing: 24) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)

            Text("Verification Cancelled")
                .font(.title2)
                .fontWeight(.bold)

            Text("The verification was cancelled. You can try again at any time.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(action: { showVerificationFlow = false }) {
                Text("Close")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Computed Properties

    private var statusText: String {
        switch verificationState {
        case .unknown:
            return "Unknown"
        case .verified:
            return "Verified"
        case .unverified:
            return "Not Verified"
        }
    }

    private var statusColor: Color {
        switch verificationState {
        case .verified:
            return .green
        case .unverified:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    // MARK: - Actions

    private func refreshState() {
        verificationState = MatrixService.shared.getVerificationState()
    }

    private func startVerification() {
        isLoading = true
        flowState = .requesting
        showVerificationFlow = true

        Task {
            do {
                // Get the verification controller
                let controller = try await MatrixService.shared.getSessionVerificationController()

                // Set up delegate to receive callbacks
                let delegate = DefaultSessionVerificationDelegate(
                    onRequestReceived: { details in
                        Task { @MainActor in
                            self.pendingRequest = details
                        }
                    },
                    onRequestAccepted: {
                        Task { @MainActor in
                            self.flowState = .sasStarted
                            // Start SAS verification
                            Task {
                                try? await MatrixService.shared.startSasVerification()
                            }
                        }
                    },
                    onSasStarted: {
                        Task { @MainActor in
                            self.flowState = .sasStarted
                        }
                    },
                    onVerificationData: { data in
                        Task { @MainActor in
                            self.verificationData = data
                            switch data {
                            case .emojis(let emojis, _):
                                self.flowState = .showingEmojis(emojis)
                            case .decimals(let values):
                                self.flowState = .showingDecimals(values)
                            }
                        }
                    },
                    onFailed: {
                        Task { @MainActor in
                            self.flowState = .cancelled
                            self.isLoading = false
                            self.errorMessage = "Verification failed"
                            self.showError = true
                        }
                    },
                    onCancelled: {
                        Task { @MainActor in
                            self.flowState = .cancelled
                            self.isLoading = false
                        }
                    },
                    onFinished: {
                        Task { @MainActor in
                            self.flowState = .completed
                            self.isLoading = false
                            self.refreshState()
                        }
                    }
                )

                controller.setDelegate(delegate: delegate)

                // Request device verification
                try await MatrixService.shared.requestDeviceVerification()

                await MainActor.run {
                    self.flowState = .waitingForOther
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showVerificationFlow = false
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    private func approveMatch() {
        isLoading = true

        Task {
            do {
                try await MatrixService.shared.approveVerification()

                await MainActor.run {
                    self.flowState = .completed
                    self.isLoading = false
                    self.refreshState()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    private func declineMatch() {
        isLoading = true

        Task {
            do {
                try await MatrixService.shared.declineVerification()

                await MainActor.run {
                    self.flowState = .cancelled
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    private func cancelFlow() {
        Task {
            try? await MatrixService.shared.cancelVerification()
        }
        showVerificationFlow = false
        flowState = .idle
        isLoading = false
    }
}

// MARK: - Verification Flow State

enum VerificationFlowState {
    case idle
    case requesting
    case waitingForOther
    case sasStarted
    case showingEmojis([SessionVerificationEmoji])
    case showingDecimals([UInt16])
    case completed
    case cancelled
}

// MARK: - Preview

#Preview {
    NavigationView {
        DeviceVerificationView()
    }
}

// MARK: - Default Session Verification Delegate

final class DefaultSessionVerificationDelegate: SessionVerificationControllerDelegate, @unchecked Sendable {
    private let onRequestReceived: (SessionVerificationRequestDetails) -> Void
    private let onRequestAccepted: () -> Void
    private let onSasStarted: () -> Void
    private let onVerificationData: (SessionVerificationData) -> Void
    private let onFailed: () -> Void
    private let onCancelled: () -> Void
    private let onFinished: () -> Void

    init(
        onRequestReceived: @escaping (SessionVerificationRequestDetails) -> Void,
        onRequestAccepted: @escaping () -> Void,
        onSasStarted: @escaping () -> Void,
        onVerificationData: @escaping (SessionVerificationData) -> Void,
        onFailed: @escaping () -> Void,
        onCancelled: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.onRequestReceived = onRequestReceived
        self.onRequestAccepted = onRequestAccepted
        self.onSasStarted = onSasStarted
        self.onVerificationData = onVerificationData
        self.onFailed = onFailed
        self.onCancelled = onCancelled
        self.onFinished = onFinished
    }

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {
        onRequestReceived(details)
    }

    func didAcceptVerificationRequest() {
        onRequestAccepted()
    }

    func didStartSasVerification() {
        onSasStarted()
    }

    func didReceiveVerificationData(data: SessionVerificationData) {
        onVerificationData(data)
    }

    func didFail() {
        onFailed()
    }

    func didCancel() {
        onCancelled()
    }

    func didFinish() {
        onFinished()
    }
}
