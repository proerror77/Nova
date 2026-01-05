import SwiftUI

// MARK: - Block/Report Sheet
/// 封鎖/舉報用戶的底部彈出選單
struct BlockReportSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Target user info
    let userId: String
    let username: String

    // State
    @State private var showReportReasons = false
    @State private var selectedReason: ReportReason?
    @State private var reportDetails: String = ""
    @State private var isProcessing = false
    @State private var showConfirmBlock = false
    @State private var showSuccess = false
    @State private var successMessage = ""

    // Services
    private let relationshipsService = RelationshipsService.shared

    // Callbacks
    var onBlocked: (() -> Void)?
    var onReported: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showReportReasons {
                    reportReasonsView
                } else {
                    mainActionsView
                }
            }
            .navigationTitle(showReportReasons ? "Select Report Reason" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showReportReasons ? "返回" : "取消") {
                        if showReportReasons {
                            withAnimation {
                                showReportReasons = false
                                selectedReason = nil
                                reportDetails = ""
                            }
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .overlay {
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }
            .alert("Confirm Block", isPresented: $showConfirmBlock) {
                Button("Cancel", role: .cancel) { }
                Button("Block", role: .destructive) {
                    Task {
                        await blockUser()
                    }
                }
            } message: {
                Text("After blocking @\(username), they won't be able to view your profile, posts, or send you messages.")
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(successMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Main Actions View
    private var mainActionsView: some View {
        VStack(spacing: 16) {
            // User avatar and name header
            VStack(spacing: 8) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Text(username.prefix(1).uppercased())
                            .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                            .foregroundColor(.gray)
                    }

                Text("@\(username)")
                    .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                    .foregroundColor(.primary)
            }
            .padding(.top, 20)

            Divider()
                .padding(.vertical, 8)

            // Action buttons
            VStack(spacing: 0) {
                // Block User
                Button {
                    showConfirmBlock = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 20.f))
                            .foregroundColor(.red)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Block @\(username)")
                                .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                                .foregroundColor(.primary)

                            Text("They won't be able to interact with you")
                                .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14.f))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }

                Divider()
                    .padding(.leading, 64)

                // Report User
                Button {
                    withAnimation {
                        showReportReasons = true
                    }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 20.f))
                            .foregroundColor(.orange)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Report @\(username)")
                                .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                                .foregroundColor(.primary)

                            Text("Report violations to us")
                                .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14.f))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    // MARK: - Report Reasons View
    private var reportReasonsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Reason selection
                VStack(spacing: 0) {
                    ForEach(ReportReason.allCases) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reason.displayName)
                                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                                        .foregroundColor(.primary)

                                    Text(reason.description)
                                        .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                if selectedReason == reason {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22.f))
                                        .foregroundColor(DesignTokens.accentColor)
                                } else {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        if reason != ReportReason.allCases.last {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)

                // Additional details (shown when "other" is selected)
                if selectedReason == .other {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional Details")
                            .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        TextEditor(text: $reportDetails)
                            .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                            .frame(minHeight: 100)
                            .padding(12)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                    }
                }

                // Submit button
                Button {
                    Task {
                        await submitReport()
                    }
                } label: {
                    Text("Submit Report")
                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selectedReason != nil
                                ? DesignTokens.accentColor
                                : Color.gray.opacity(0.5)
                        )
                        .cornerRadius(12)
                }
                .disabled(selectedReason == nil)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
                    .frame(height: 40)
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Actions

    private func blockUser() async {
        isProcessing = true

        do {
            try await relationshipsService.blockUser(userId: userId, reason: nil)
            await MainActor.run {
                isProcessing = false
                successMessage = "已成功封鎖 @\(username)"
                showSuccess = true
                onBlocked?()
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                // TODO: Show error alert
                print("❌ Failed to block user: \(error)")
            }
        }
    }

    private func submitReport() async {
        guard let reason = selectedReason else { return }

        isProcessing = true

        do {
            let details = reportDetails.isEmpty ? nil : reportDetails
            try await relationshipsService.reportUser(userId: userId, reason: reason, details: details)
            await MainActor.run {
                isProcessing = false
                successMessage = "感謝你的舉報，我們會儘快處理"
                showSuccess = true
                onReported?()
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                // TODO: Show error alert
                print("❌ Failed to report user: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview("Block/Report Sheet") {
    BlockReportSheet(
        userId: "user-123",
        username: "test_user"
    )
}
