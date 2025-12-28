import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat Backup View

/// View for managing chat backups - export and import conversations
struct ChatBackupView: View {
    @Binding var currentPage: AppPage

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showExportSheet = false
    @State private var showImportPicker = false
    @State private var exportedFileURL: URL?
    @State private var importResult: ChatBackupService.ImportResult?
    @State private var backupInfo: ChatBackupService.BackupInfo?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let backupService = ChatBackupService.shared

    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation Bar
                navigationBar

                ScrollView {
                    VStack(spacing: 20) {
                        // Export Section
                        exportSection

                        // Import Section
                        importSection

                        // Info Section
                        infoSection
                    }
                    .padding(.top, 20)
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .overlay(alignment: .top) {
            if let error = errorMessage {
                NotificationBanner(message: error, isError: true)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            errorMessage = nil
                        }
                    }
            }

            if let success = successMessage {
                NotificationBanner(message: success, isError: false)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            successMessage = nil
                        }
                    }
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
                    .frame(width: 24, height: 24)
                    .foregroundColor(DesignTokens.textPrimary)
            }

            Spacer()

            Text("Chat Backup")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignTokens.textPrimary)

            Spacer()

            Color.clear
                .frame(width: 24)
        }
        .frame(height: DesignTokens.topBarHeight)
        .padding(.horizontal, 16)
        .background(DesignTokens.surface)
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignTokens.textSecondary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                // Export All Chats
                Button(action: exportAllChats) {
                    HStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(DesignTokens.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export All Chats")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignTokens.textPrimary)

                            Text("Save all conversations to a backup file")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        Spacer()

                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .disabled(isExporting)
            }
            .background(DesignTokens.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignTokens.textSecondary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                Button(action: { showImportPicker = true }) {
                    HStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18))
                            .foregroundColor(DesignTokens.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Backup")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignTokens.textPrimary)

                            Text("Restore conversations from a backup file")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        Spacer()

                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .disabled(isImporting)
            }
            .background(DesignTokens.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Backups")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignTokens.textSecondary)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                InfoRow(icon: "lock.shield", text: "Backups are stored locally on your device")
                InfoRow(icon: "doc.text", text: "Exported as JSON format for portability")
                InfoRow(icon: "photo", text: "Media URLs are included but files are not embedded")
                InfoRow(icon: "clock", text: "Regular backups are recommended")
            }
            .padding(16)
            .background(DesignTokens.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Actions

    private func exportAllChats() {
        isExporting = true

        Task {
            do {
                let url = try await backupService.exportAllConversations()
                exportedFileURL = url
                showExportSheet = true
                successMessage = "Backup created successfully"
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isImporting = true

            Task {
                do {
                    let importResult = try await backupService.importBackup(from: url)
                    self.importResult = importResult

                    if importResult.isSuccess {
                        successMessage = "Imported \(importResult.importedConversations) conversations"
                    } else {
                        errorMessage = "Import completed with \(importResult.errors.count) errors"
                    }
                } catch {
                    errorMessage = "Import failed: \(error.localizedDescription)"
                }
                isImporting = false
            }

        case .failure(let error):
            errorMessage = "Could not read file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Views

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.accentColor)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(DesignTokens.textSecondary)

            Spacer()
        }
    }
}

private struct NotificationBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
            .cornerRadius(8)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut, value: message)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ChatBackupView(currentPage: .constant(.chatBackup))
}
