import SwiftUI
import AuthenticationServices

// MARK: - Passkey Settings View

/// 管理用戶的 Passkey（WebAuthn/FIDO2）憑證
/// 支援查看、新增、重新命名和刪除 Passkey
@available(iOS 16.0, *)
struct PasskeySettingsView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var passkeys: [PasskeyService.PasskeyInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPasskey: PasskeyService.PasskeyInfo?
    @State private var showDeleteConfirmation = false
    @State private var passkeyToDelete: PasskeyService.PasskeyInfo?
    @State private var showRenameDialog = false
    @State private var passkeyToRename: PasskeyService.PasskeyInfo?
    @State private var newPasskeyName = ""
    @State private var isAddingPasskey = false
    @State private var showAddSuccess = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 頂部導航欄
                navigationBar

                // MARK: - 內容區域
                ZStack {
                    if isLoading && passkeys.isEmpty {
                        loadingView
                    } else if let errorMessage = errorMessage, passkeys.isEmpty {
                        errorView(message: errorMessage)
                    } else if passkeys.isEmpty {
                        emptyView
                    } else {
                        passkeyListView
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .task {
            await loadPasskeys()
        }
        .alert("Delete Passkey", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let passkey = passkeyToDelete {
                    Task {
                        await deletePasskey(passkey)
                    }
                }
            }
        } message: {
            if let passkey = passkeyToDelete {
                Text("Are you sure you want to delete \"\(passkey.credentialName ?? "Passkey")\"? You won't be able to sign in with this Passkey after deletion.")
            }
        }
        .alert("Rename Passkey", isPresented: $showRenameDialog) {
            TextField("Passkey Name", text: $newPasskeyName)
            Button("Cancel", role: .cancel) {
                newPasskeyName = ""
            }
            Button("Save") {
                if let passkey = passkeyToRename {
                    Task {
                        await renamePasskey(passkey, newName: newPasskeyName)
                        newPasskeyName = ""
                    }
                }
            }
        } message: {
            Text("Enter a new name for this Passkey")
        }
        .sheet(item: $selectedPasskey) { passkey in
            PasskeyDetailSheet(
                passkey: passkey,
                onRename: {
                    selectedPasskey = nil
                    passkeyToRename = passkey
                    newPasskeyName = passkey.credentialName ?? ""
                    showRenameDialog = true
                },
                onDelete: {
                    selectedPasskey = nil
                    passkeyToDelete = passkey
                    showDeleteConfirmation = true
                }
            )
        }
        .overlay {
            if showAddSuccess {
                successToast
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button(action: {
                currentPage = .setting
            }) {
                Image(systemName: "chevron.left")
                    .font(Font.custom("SFProDisplay-Semibold", size: 17.f))
                    .foregroundColor(DesignTokens.accentColor)
            }

            Spacer()

            Text("Passkeys")
                .font(Font.custom("SFProDisplay-Semibold", size: 17.f))
                .foregroundColor(DesignTokens.textPrimary)

            Spacer()

            // 新增 Passkey 按鈕
            Button(action: {
                Task {
                    await addPasskey()
                }
            }) {
                if isAddingPasskey {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus")
                        .font(Font.custom("SFProDisplay-Semibold", size: 17.f))
                        .foregroundColor(DesignTokens.accentColor)
                }
            }
            .disabled(isAddingPasskey)
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(Font.custom("SFProDisplay-Regular", size: 48.f))
                .foregroundColor(.secondary)

            Text(message)
                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Retry") {
                Task {
                    await loadPasskeys()
                }
            }
            .font(Font.custom("SFProDisplay-Medium", size: 17.f))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(DesignTokens.accentColor)
            .cornerRadius(10)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.key.fill")
                .font(Font.custom("SFProDisplay-Regular", size: 64.f))
                .foregroundColor(.secondary.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Passkeys Set Up")
                    .font(Font.custom("SFProDisplay-Semibold", size: 20.f))
                    .foregroundColor(.primary)

                Text("Passkeys let you sign in quickly and securely using Face ID or Touch ID, without needing a password.")
                    .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                Task {
                    await addPasskey()
                }
            }) {
                HStack(spacing: 8) {
                    if isAddingPasskey {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Passkey")
                    }
                }
                .font(Font.custom("SFProDisplay-Semibold", size: 17.f))
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(DesignTokens.accentColor)
                .cornerRadius(12)
            }
            .disabled(isAddingPasskey)
            .padding(.top, 8)
        }
    }

    // MARK: - Passkey List View

    private var passkeyListView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Passkey 列表
                VStack(alignment: .leading, spacing: 8) {
                    Text("REGISTERED PASSKEYS")
                        .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ForEach(Array(passkeys.enumerated()), id: \.element.id) { index, passkey in
                            PasskeyRow(
                                passkey: passkey,
                                isFirst: index == 0,
                                isLast: index == passkeys.count - 1,
                                onTap: { selectedPasskey = passkey },
                                onDelete: {
                                    passkeyToDelete = passkey
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }

                // 說明文字
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "faceid")
                            .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                            .foregroundColor(DesignTokens.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fast & Secure Sign-in")
                                .font(Font.custom("SFProDisplay-Semibold", size: 15.f))
                                .foregroundColor(.primary)
                            Text("Use Face ID or Touch ID to verify your identity, more secure than passwords.")
                                .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "icloud.fill")
                            .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                            .foregroundColor(DesignTokens.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud Sync")
                                .font(Font.custom("SFProDisplay-Semibold", size: 15.f))
                                .foregroundColor(.primary)
                            Text("Passkeys automatically sync to all your Apple devices via iCloud Keychain.")
                                .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .refreshable {
            await loadPasskeys()
        }
    }

    // MARK: - Success Toast

    private var successToast: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                    .foregroundColor(.green)

                Text("Passkey Added")
                    .font(Font.custom("SFProDisplay-Medium", size: 15.f))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: showAddSuccess)
    }

    // MARK: - Actions

    private func loadPasskeys() async {
        isLoading = true
        errorMessage = nil

        do {
            passkeys = try await PasskeyService.shared.listPasskeys()
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
            print("[PasskeySettings] Failed to load passkeys: \(error)")
        }

        isLoading = false
    }

    private func addPasskey() async {
        isAddingPasskey = true

        do {
            let deviceName = await MainActor.run {
                UIDevice.current.name
            }
            _ = try await PasskeyService.shared.registerPasskey(credentialName: deviceName)
            await loadPasskeys()

            // 顯示成功提示
            withAnimation {
                showAddSuccess = true
            }

            // 2 秒後隱藏
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showAddSuccess = false
            }
        } catch {
            errorMessage = "Failed to add: \(error.localizedDescription)"
            print("[PasskeySettings] Failed to add passkey: \(error)")
        }

        isAddingPasskey = false
    }

    private func deletePasskey(_ passkey: PasskeyService.PasskeyInfo) async {
        do {
            try await PasskeyService.shared.revokePasskey(credentialId: passkey.id)
            passkeys.removeAll { $0.id == passkey.id }
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
            print("[PasskeySettings] Failed to delete passkey: \(error)")
        }
    }

    private func renamePasskey(_ passkey: PasskeyService.PasskeyInfo, newName: String) async {
        guard !newName.isEmpty else { return }

        do {
            try await PasskeyService.shared.renamePasskey(credentialId: passkey.id, newName: newName)
            await loadPasskeys()
        } catch {
            errorMessage = "Failed to rename: \(error.localizedDescription)"
            print("[PasskeySettings] Failed to rename passkey: \(error)")
        }
    }
}

// MARK: - Passkey Row

@available(iOS 16.0, *)
private struct PasskeyRow: View {
    let passkey: PasskeyService.PasskeyInfo
    let isFirst: Bool
    let isLast: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Passkey 圖標
                ZStack {
                    Circle()
                        .fill(DesignTokens.accentColor)
                        .frame(width: 44, height: 44)

                    Image(systemName: passkeyIcon)
                        .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                        .foregroundColor(.white)
                }

                // Passkey 資訊
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(passkey.credentialName ?? "Passkey")
                            .font(Font.custom("SFProDisplay-Regular", size: 17.f))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if passkey.backupState {
                            Image(systemName: "icloud.fill")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.blue)
                        }
                    }

                    Text(passkeySubtitle)
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // 刪除按鈕
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)

                Image(systemName: "chevron.right")
                    .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .buttonStyle(.plain)
        .clipShape(
            RoundedCorners(
                topLeft: isFirst ? 10 : 0,
                topRight: isFirst ? 10 : 0,
                bottomLeft: isLast ? 10 : 0,
                bottomRight: isLast ? 10 : 0
            )
        )
        .overlay(
            VStack {
                Spacer()
                if !isLast {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: 0.5)
                        .padding(.leading, 74)
                }
            }
        )
        .padding(.horizontal, 16)
    }

    private var passkeyIcon: String {
        if let deviceType = passkey.deviceType?.lowercased() {
            if deviceType.contains("iphone") {
                return "iphone"
            } else if deviceType.contains("ipad") {
                return "ipad"
            } else if deviceType.contains("mac") {
                return "laptopcomputer"
            }
        }
        return "person.badge.key.fill"
    }

    private var passkeySubtitle: String {
        var parts: [String] = []

        if let deviceType = passkey.deviceType {
            parts.append(deviceType)
        }

        if let lastUsed = passkey.lastUsedAt {
            let date = Date(timeIntervalSince1970: TimeInterval(lastUsed))
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            parts.append("Last used: \(formatter.localizedString(for: date, relativeTo: Date()))")
        } else {
            let date = Date(timeIntervalSince1970: TimeInterval(passkey.createdAt))
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            parts.append("Created on \(formatter.string(from: date))")
        }

        return parts.joined(separator: " · ")
    }
}

// MARK: - Passkey Detail Sheet

@available(iOS 16.0, *)
private struct PasskeyDetailSheet: View {
    let passkey: PasskeyService.PasskeyInfo
    let onRename: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // 基本資訊
                Section {
                    LabeledContent("Name", value: passkey.credentialName ?? "Passkey")
                    if let deviceType = passkey.deviceType {
                        LabeledContent("Device Type", value: deviceType)
                    }
                    if let osVersion = passkey.osVersion {
                        LabeledContent("OS Version", value: osVersion)
                    }
                }

                // 同步狀態
                Section {
                    HStack {
                        Text("iCloud Sync")
                        Spacer()
                        if passkey.backupState {
                            Label("Synced", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if passkey.backupEligible {
                            Label("Syncable", systemImage: "icloud")
                                .foregroundColor(.blue)
                        } else {
                            Label("This Device Only", systemImage: "iphone")
                                .foregroundColor(.orange)
                        }
                    }
                } footer: {
                    if passkey.backupState {
                        Text("This Passkey is synced to your iCloud Keychain and available on all your Apple devices.")
                    } else if passkey.backupEligible {
                        Text("This Passkey can be synced to iCloud Keychain.")
                    } else {
                        Text("This Passkey is stored only on this device and cannot be synced to other devices.")
                    }
                }

                // 使用記錄
                Section {
                    LabeledContent("Created", value: formatDate(passkey.createdAt))
                    if let lastUsed = passkey.lastUsedAt {
                        LabeledContent("Last Used", value: formatDate(lastUsed))
                    }
                }

                // Transport methods
                if !passkey.transports.isEmpty {
                    Section("Supported Transport Methods") {
                        ForEach(passkey.transports, id: \.self) { transport in
                            Label(transportName(transport), systemImage: transportIcon(transport))
                        }
                    }
                }

                // 操作按鈕
                Section {
                    Button {
                        dismiss()
                        onRename()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        dismiss()
                        onDelete()
                    } label: {
                        Label("Delete Passkey", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Passkey Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func transportName(_ transport: String) -> String {
        switch transport.lowercased() {
        case "internal":
            return "Built-in Authenticator"
        case "usb":
            return "USB Security Key"
        case "nfc":
            return "NFC"
        case "ble":
            return "Bluetooth"
        case "hybrid":
            return "Cross-Device"
        default:
            return transport
        }
    }

    private func transportIcon(_ transport: String) -> String {
        switch transport.lowercased() {
        case "internal":
            return "faceid"
        case "usb":
            return "cable.connector"
        case "nfc":
            return "wave.3.right"
        case "ble":
            return "bluetooth"
        case "hybrid":
            return "iphone.and.arrow.forward"
        default:
            return "questionmark.circle"
        }
    }
}

// MARK: - Previews

@available(iOS 16.0, *)
#Preview("Passkey Settings") {
    PasskeySettingsView(currentPage: .constant(.passkeys))
        .environmentObject(AuthenticationManager.shared)
}
