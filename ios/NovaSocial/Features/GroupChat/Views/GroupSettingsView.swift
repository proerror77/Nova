import SwiftUI

/// View for managing group chat settings
/// Features: member list, group info, leave group, mute notifications
struct GroupSettingsView: View {
    @Binding var isPresented: Bool
    let conversationId: String
    let groupName: String
    let memberCount: Int

    @State private var members: [GroupMemberDisplayInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMuted = false
    @State private var showLeaveConfirmation = false
    @State private var isLeaving = false

    private let matrixBridge = MatrixBridgeService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundColor
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading...")
                        .foregroundColor(DesignTokens.textSecondary)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(Font.custom("SFProDisplay-Regular", size: 40.f))
                            .foregroundColor(DesignTokens.accentColor)
                        Text(error)
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(DesignTokens.textSecondary)
                        Button("Retry") {
                            Task { await loadGroupDetails() }
                        }
                        .foregroundColor(DesignTokens.accentColor)
                    }
                } else {
                    List {
                        // Group Info Section
                        Section {
                            groupInfoRow
                        }

                        // Members Section
                        Section {
                            ForEach(members) { member in
                                MemberRow(member: member)
                            }
                        } header: {
                            Text("Members (\(members.count))")
                                .font(Font.custom("SFProDisplay-Semibold", size: 13.f))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        // Settings Section
                        Section {
                            muteToggleRow
                        } header: {
                            Text("Notifications")
                                .font(Font.custom("SFProDisplay-Semibold", size: 13.f))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        // Actions Section
                        Section {
                            leaveGroupButton
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Group Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(DesignTokens.textPrimary)
                }
            }
        }
        .task {
            await loadGroupDetails()
        }
        .alert("Leave Group", isPresented: $showLeaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task { await leaveGroup() }
            }
        } message: {
            Text("Are you sure you want to leave \"\(groupName)\"? You will no longer receive messages from this group.")
        }
    }

    // MARK: - Group Info Row

    private var groupInfoRow: some View {
        HStack(spacing: 16) {
            // Group avatar
            ZStack {
                Circle()
                    .fill(DesignTokens.accentColor.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: "person.3.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                    .foregroundColor(DesignTokens.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(groupName)
                    .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                    .foregroundColor(DesignTokens.textPrimary)

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(.green)
                    Text("End-to-end encrypted")
                        .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                        .foregroundColor(DesignTokens.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .listRowBackground(DesignTokens.surface)
    }

    // MARK: - Mute Toggle Row

    private var muteToggleRow: some View {
        Toggle(isOn: $isMuted) {
            HStack(spacing: 12) {
                Image(systemName: isMuted ? "bell.slash.fill" : "bell.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                    .foregroundColor(DesignTokens.textPrimary)
                    .frame(width: 28)

                Text("Mute Notifications")
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                    .foregroundColor(DesignTokens.textPrimary)
            }
        }
        .tint(DesignTokens.accentColor)
        .listRowBackground(DesignTokens.surface)
    }

    // MARK: - Leave Group Button

    private var leaveGroupButton: some View {
        Button(action: {
            showLeaveConfirmation = true
        }) {
            HStack {
                Spacer()
                if isLeaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                } else {
                    Text("Leave Group")
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(.red)
                }
                Spacer()
            }
        }
        .disabled(isLeaving)
        .listRowBackground(DesignTokens.surface)
    }

    // MARK: - Load Group Details

    private func loadGroupDetails() async {
        isLoading = true
        errorMessage = nil

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Get real members from Matrix SDK
            let roomMembers = try await matrixBridge.getConversationMembers(conversationId: conversationId)

            // Convert to display info
            members = roomMembers.map { member in
                // Extract username from Matrix user ID (e.g., "@username:server" -> "username")
                let displayName = member.displayName ?? extractUsername(from: member.userId)

                return GroupMemberDisplayInfo(
                    id: member.userId,
                    displayName: displayName,
                    avatarUrl: member.avatarUrl,
                    isAdmin: member.isAdmin
                )
            }

            // Sort: admins first, then by display name
            members.sort { first, second in
                if first.isAdmin != second.isAdmin {
                    return first.isAdmin
                }
                return first.displayName < second.displayName
            }

            #if DEBUG
            print("[GroupSettingsView] Loaded \(members.count) real members")
            #endif

        } catch {
            errorMessage = "Failed to load group details"
            #if DEBUG
            print("[GroupSettingsView] Error: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Leave Group

    private func leaveGroup() async {
        isLeaving = true

        do {
            try await matrixBridge.leaveRoom(roomId: conversationId)
            isPresented = false
        } catch {
            errorMessage = "Failed to leave group"
            #if DEBUG
            print("[GroupSettingsView] Leave error: \(error)")
            #endif
        }

        isLeaving = false
    }

    // MARK: - Helpers

    private func extractUsername(from matrixUserId: String) -> String {
        if matrixUserId.hasPrefix("@") {
            let parts = matrixUserId.dropFirst().split(separator: ":")
            if let username = parts.first {
                return String(username)
            }
        }
        return matrixUserId
    }
}

// MARK: - Member Display Info

struct GroupMemberDisplayInfo: Identifiable {
    let id: String
    let displayName: String
    let avatarUrl: String?
    let isAdmin: Bool
}

// MARK: - Member Row

private struct MemberRow: View {
    let member: GroupMemberDisplayInfo

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
            }

            // Name and role
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                    .foregroundColor(DesignTokens.textPrimary)

                if member.isAdmin {
                    Text("Admin")
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(DesignTokens.accentColor)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(DesignTokens.surface)
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(DesignTokens.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)

            Text(String(member.displayName.prefix(1)).uppercased())
                .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                .foregroundColor(DesignTokens.accentColor)
        }
    }
}

#Preview {
    GroupSettingsView(
        isPresented: .constant(true),
        conversationId: "!room:matrix.org",
        groupName: "Test Group",
        memberCount: 5
    )
}
