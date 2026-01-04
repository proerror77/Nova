import SwiftUI

/// View for selecting an existing group chat
struct GroupSelectionView: View {
    @Binding var isPresented: Bool
    let onGroupSelected: (String, String, Int) -> Void  // (conversationId, groupName, memberCount)

    @State private var groups: [MatrixBridgeService.MatrixConversationInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let matrixBridge = MatrixBridgeService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundColor
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading groups...")
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
                            Task { await loadGroups() }
                        }
                        .foregroundColor(DesignTokens.accentColor)
                    }
                } else if groups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(Font.custom("SFProDisplay-Regular", size: 40.f))
                            .foregroundColor(DesignTokens.textSecondary)
                        Text("No groups yet")
                            .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                            .foregroundColor(DesignTokens.textSecondary)
                        Text("Create a new group chat to get started")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(DesignTokens.textMuted)
                    }
                } else {
                    List {
                        ForEach(groups) { group in
                            Button {
                                onGroupSelected(group.id, group.displayName, group.memberCount)
                                isPresented = false
                            } label: {
                                GroupRow(group: group)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Select Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(DesignTokens.textPrimary)
                }
            }
        }
        .task {
            await loadGroups()
        }
    }

    private func loadGroups() async {
        isLoading = true
        errorMessage = nil

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            let allConversations = try await matrixBridge.getConversationsFromMatrix()
            // Filter for group chats only (isDirect == false)
            groups = allConversations.filter { !$0.isDirect }

            #if DEBUG
            print("[GroupSelectionView] Loaded \(groups.count) groups")
            #endif
        } catch {
            errorMessage = "Failed to load groups"
            #if DEBUG
            print("[GroupSelectionView] Error: \(error)")
            #endif
        }

        isLoading = false
    }
}

// MARK: - Group Row Component
private struct GroupRow: View {
    let group: MatrixBridgeService.MatrixConversationInfo

    var body: some View {
        HStack(spacing: 12) {
            // Group avatar
            ZStack {
                Circle()
                    .fill(DesignTokens.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: "person.3.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                    .foregroundColor(DesignTokens.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                        .foregroundColor(DesignTokens.textPrimary)

                    if group.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .foregroundColor(.green)
                    }
                }

                Text("\(group.memberCount) members")
                    .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                    .foregroundColor(DesignTokens.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(DesignTokens.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.backgroundColor)
    }
}

#Preview {
    GroupSelectionView(isPresented: .constant(true)) { _, _, _ in }
}
