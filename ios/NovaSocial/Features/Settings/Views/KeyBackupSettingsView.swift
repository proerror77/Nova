import SwiftUI
import MatrixRustSDK

// MARK: - Key Backup Settings View

/// View for managing Matrix E2EE key backup and recovery
struct KeyBackupSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var backupState: BackupState = .unknown
    @State private var recoveryState: RecoveryState = .unknown
    @State private var isLoading = false
    @State private var showRecoveryKeySheet = false
    @State private var showEnterRecoveryKeySheet = false
    @State private var recoveryKey: String = ""
    @State private var enteredRecoveryKey: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showCopyConfirmation = false
    @State private var backupProgress: (backed: UInt32, total: UInt32)?

    // MARK: - Body

    var body: some View {
        List {
            // Status Section
            Section {
                statusRow(title: "Backup Status", status: backupStatusText, color: backupStatusColor)
                statusRow(title: "Recovery Status", status: recoveryStatusText, color: recoveryStatusColor)
            } header: {
                Text("Encryption Status")
            } footer: {
                Text("Key backup ensures you can access your encrypted messages on new devices.")
            }

            // Actions Section
            Section {
                if recoveryState == .disabled || recoveryState == .unknown {
                    Button(action: setupBackup) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.blue)
                            Text("Set Up Key Backup")
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(isLoading)
                }

                if recoveryState == .enabled || recoveryState == .incomplete {
                    Button(action: { showEnterRecoveryKeySheet = true }) {
                        HStack {
                            Image(systemName: "arrow.down.doc.fill")
                                .foregroundColor(.green)
                            Text("Restore from Backup")
                        }
                    }
                }

                if backupState == .enabled {
                    Button(action: viewRecoveryKey) {
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.orange)
                            Text("View Recovery Key")
                        }
                    }
                }
            } header: {
                Text("Actions")
            }

            // Progress Section (if backing up)
            if let progress = backupProgress {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Backing up keys...")
                            Spacer()
                            Text("\(progress.backed)/\(progress.total)")
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(progress.backed), total: Double(progress.total))
                    }
                } header: {
                    Text("Progress")
                }
            }

            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(
                        icon: "shield.checkered",
                        title: "What is Key Backup?",
                        description: "Key backup securely stores your encryption keys so you can read your message history on new devices."
                    )

                    Divider()

                    infoRow(
                        icon: "key.horizontal",
                        title: "Recovery Key",
                        description: "Your recovery key is the only way to restore your encrypted messages if you lose access to all your devices. Keep it safe!"
                    )

                    Divider()

                    infoRow(
                        icon: "lock.shield",
                        title: "Security",
                        description: "Your keys are encrypted before being uploaded. Only you can decrypt them with your recovery key."
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Text("About Key Backup")
            }
        }
        .navigationTitle("Key Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshState()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showRecoveryKeySheet) {
            recoveryKeySheet
        }
        .sheet(isPresented: $showEnterRecoveryKeySheet) {
            enterRecoveryKeySheet
        }
        .overlay {
            if showCopyConfirmation {
                copyConfirmationOverlay
            }
        }
    }

    // MARK: - Subviews

    private func statusRow(title: String, status: String, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(status)
                .foregroundColor(color)
                .fontWeight(.medium)
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

    private var recoveryKeySheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60.f))
                    .foregroundColor(.orange)

                Text("Your Recovery Key")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Save this key in a secure location. You'll need it to restore your encrypted messages on new devices.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Recovery Key Display
                VStack(spacing: 12) {
                    Text(recoveryKey)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .textSelection(.enabled)

                    Button(action: copyRecoveryKey) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy to Clipboard")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                Spacer()

                Text("Warning: If you lose this key and all your devices, you won't be able to read your encrypted message history.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Recovery Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showRecoveryKeySheet = false
                    }
                }
            }
        }
    }

    private var enterRecoveryKeySheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 60.f))
                    .foregroundColor(.green)

                Text("Enter Recovery Key")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Enter your recovery key to restore access to your encrypted messages.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Recovery Key", text: $enteredRecoveryKey)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal)

                Button(action: restoreFromBackup) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Restore")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(enteredRecoveryKey.isEmpty ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(enteredRecoveryKey.isEmpty || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showEnterRecoveryKeySheet = false
                        enteredRecoveryKey = ""
                    }
                }
            }
        }
    }

    private var copyConfirmationOverlay: some View {
        VStack {
            Text("Copied!")
                .font(.headline)
                .padding()
                .background(Color.black.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .transition(.opacity)
        .animation(.easeInOut, value: showCopyConfirmation)
    }

    // MARK: - Computed Properties

    private var backupStatusText: String {
        switch backupState {
        case .unknown:
            return "Unknown"
        case .creating:
            return "Creating..."
        case .enabling:
            return "Enabling..."
        case .resuming:
            return "Resuming..."
        case .enabled:
            return "Enabled"
        case .downloading:
            return "Downloading..."
        case .disabling:
            return "Disabling..."
        }
    }

    private var backupStatusColor: Color {
        switch backupState {
        case .enabled:
            return .green
        case .unknown:
            return .secondary
        case .creating, .enabling, .resuming, .downloading, .disabling:
            return .orange
        }
    }

    private var recoveryStatusText: String {
        switch recoveryState {
        case .unknown:
            return "Unknown"
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        case .incomplete:
            return "Incomplete"
        }
    }

    private var recoveryStatusColor: Color {
        switch recoveryState {
        case .enabled:
            return .green
        case .disabled:
            return .red
        case .incomplete:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    // MARK: - Actions

    private func refreshState() {
        backupState = MatrixService.shared.getBackupState()
        recoveryState = MatrixService.shared.getRecoveryState()
    }

    private func setupBackup() {
        isLoading = true

        Task {
            do {
                // Create progress listener
                let progressListener = CallbackEnableRecoveryProgressListener { progress in
                    Task { @MainActor in
                        switch progress {
                        case .backingUp(let backed, let total):
                            self.backupProgress = (backed, total)
                        case .done(let key):
                            self.recoveryKey = key
                            self.backupProgress = nil
                        default:
                            break
                        }
                    }
                }

                let key = try await MatrixService.shared.enableRecovery(
                    waitForBackupsToUpload: true,
                    passphrase: nil,
                    progressListener: progressListener
                )

                await MainActor.run {
                    self.recoveryKey = key
                    self.isLoading = false
                    self.showRecoveryKeySheet = true
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

    private func viewRecoveryKey() {
        // Note: The SDK doesn't provide a way to retrieve the recovery key after initial setup
        // User should have saved it. Show a message instead.
        errorMessage = "Your recovery key was shown when you first set up backup. If you didn't save it, you can reset your backup to get a new key."
        showError = true
    }

    private func restoreFromBackup() {
        isLoading = true

        Task {
            do {
                try await MatrixService.shared.recoverFromBackup(recoveryKey: enteredRecoveryKey)

                await MainActor.run {
                    self.isLoading = false
                    self.showEnterRecoveryKeySheet = false
                    self.enteredRecoveryKey = ""
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

    private func copyRecoveryKey() {
        UIPasteboard.general.string = recoveryKey
        showCopyConfirmation = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopyConfirmation = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        KeyBackupSettingsView()
    }
}
