import SwiftUI

// MARK: - Friend Requests ViewModel

/// FriendRequestsViewModel - 好友請求管理的 ViewModel
/// 處理收到/發送的好友請求列表和接受/拒絕操作
@MainActor
@Observable
class FriendRequestsViewModel {
    // MARK: - Properties

    var selectedTab: FriendRequestType = .received
    var receivedRequests: [FriendRequestWithUser] = []
    var sentRequests: [FriendRequestWithUser] = []
    var isLoading: Bool = false
    var isProcessing: Bool = false  // For accept/reject/cancel operations
    var errorMessage: String?
    var toastMessage: String?
    var pendingCount: Int = 0

    private let friendsService = FriendsService()

    // MARK: - Load Requests

    /// 加載待處理的好友請求
    func loadRequests() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load both received and sent requests in parallel
            async let receivedTask = friendsService.getPendingRequests(type: .received, limit: 50, offset: 0)
            async let sentTask = friendsService.getPendingRequests(type: .sent, limit: 50, offset: 0)
            async let countTask = friendsService.getPendingRequestCount()

            let (received, sent, count) = try await (receivedTask, sentTask, countTask)

            receivedRequests = received.requests
            sentRequests = sent.requests
            pendingCount = count

            #if DEBUG
            print("[FriendRequests] Loaded \(receivedRequests.count) received, \(sentRequests.count) sent requests")
            #endif
        } catch {
            if case APIError.serverError(let statusCode, _) = error, statusCode == 501 || statusCode == 503 {
                // Endpoint not deployed yet - show empty state
                receivedRequests = []
                sentRequests = []
                pendingCount = 0
                #if DEBUG
                print("[FriendRequests] Endpoint not deployed yet")
                #endif
            } else {
                errorMessage = "Failed to load friend requests: \(error.localizedDescription)"
                #if DEBUG
                print("❌ Failed to load friend requests: \(error)")
                #endif
            }
        }

        isLoading = false
    }

    // MARK: - Accept Request

    /// 接受好友請求
    func acceptRequest(_ requestId: String) async {
        isProcessing = true
        errorMessage = nil

        do {
            try await friendsService.acceptFriendRequest(requestId: requestId)

            // Remove from received list
            receivedRequests.removeAll { $0.id == requestId }
            pendingCount = max(0, pendingCount - 1)

            showToast("Friend request accepted")

            #if DEBUG
            print("[FriendRequests] Accepted request: \(requestId)")
            #endif
        } catch {
            errorMessage = "Failed to accept request: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to accept request: \(error)")
            #endif
        }

        isProcessing = false
    }

    // MARK: - Reject Request

    /// 拒絕好友請求
    func rejectRequest(_ requestId: String) async {
        isProcessing = true
        errorMessage = nil

        do {
            try await friendsService.rejectFriendRequest(requestId: requestId)

            // Remove from received list
            receivedRequests.removeAll { $0.id == requestId }
            pendingCount = max(0, pendingCount - 1)

            showToast("Friend request rejected")

            #if DEBUG
            print("[FriendRequests] Rejected request: \(requestId)")
            #endif
        } catch {
            errorMessage = "Failed to reject request: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to reject request: \(error)")
            #endif
        }

        isProcessing = false
    }

    // MARK: - Cancel Request

    /// 取消已發送的好友請求
    func cancelRequest(_ requestId: String) async {
        isProcessing = true
        errorMessage = nil

        do {
            try await friendsService.cancelFriendRequest(requestId: requestId)

            // Remove from sent list
            sentRequests.removeAll { $0.id == requestId }

            showToast("Friend request cancelled")

            #if DEBUG
            print("[FriendRequests] Cancelled request: \(requestId)")
            #endif
        } catch {
            errorMessage = "Failed to cancel request: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to cancel request: \(error)")
            #endif
        }

        isProcessing = false
    }

    // MARK: - Toast Helper

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                toastMessage = nil
            }
        }
    }

    // MARK: - Current Requests

    /// 當前選中標籤的請求列表
    var currentRequests: [FriendRequestWithUser] {
        switch selectedTab {
        case .received:
            return receivedRequests
        case .sent:
            return sentRequests
        }
    }
}

// MARK: - Friend Requests View

struct FriendRequestsView: View {
    @Binding var currentPage: AppPage
    @State private var viewModel = FriendRequestsViewModel()

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Navigation Bar
                navigationBar

                Divider()

                // MARK: - Segmented Control
                segmentedControl
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                // MARK: - Error Message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                // MARK: - Content
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.currentRequests.isEmpty {
                    emptyStateView
                } else {
                    requestsList
                }
            }

            // MARK: - Toast Message
            if let toast = viewModel.toastMessage {
                toastView(message: toast)
            }
        }
        .task {
            await viewModel.loadRequests()
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button(action: {
                currentPage = .addFriends
            }) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .foregroundColor(.black)
            }

            Spacer()

            Text("Friend Requests")
                .font(Font.custom("SFProDisplay-Bold", size: 20.f))
                .foregroundColor(.black)

            Spacer()

            // Badge for pending count
            if viewModel.pendingCount > 0 {
                Text("\(viewModel.pendingCount)")
                    .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .clipShape(Capsule())
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .background(Color.white)
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            segmentButton(
                title: "Received",
                count: viewModel.receivedRequests.count,
                isSelected: viewModel.selectedTab == .received
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectedTab = .received
                }
            }

            segmentButton(
                title: "Sent",
                count: viewModel.sentRequests.count,
                isSelected: viewModel.selectedTab == .sent
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectedTab = .sent
                }
            }
        }
        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
        .cornerRadius(8)
    }

    private func segmentButton(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(isSelected ? .white : .gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .black : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white : Color.clear)
            .cornerRadius(6)
        }
        .padding(2)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading...")
            Spacer()
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: viewModel.selectedTab == .received ? "person.badge.clock" : "paperplane")
                .font(Font.custom("SFProDisplay-Regular", size: 48.f))
                .foregroundColor(.gray.opacity(0.5))

            Text(viewModel.selectedTab == .received ? "No received friend requests" : "No sent friend requests")
                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                .foregroundColor(.gray)

            if viewModel.selectedTab == .received {
                Text("When someone sends you a friend request, it will appear here")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(.gray.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Requests List

    private var requestsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.currentRequests) { request in
                    FriendRequestCardView(
                        request: request,
                        requestType: viewModel.selectedTab,
                        isProcessing: viewModel.isProcessing,
                        onAccept: {
                            Task {
                                await viewModel.acceptRequest(request.id)
                            }
                        },
                        onReject: {
                            Task {
                                await viewModel.rejectRequest(request.id)
                            }
                        },
                        onCancel: {
                            Task {
                                await viewModel.cancelRequest(request.id)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.loadRequests()
        }
    }

    // MARK: - Toast View

    private func toastView(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
                .cornerRadius(20)
                .padding(.bottom, 100)
        }
        .transition(.opacity)
        .animation(.easeInOut, value: viewModel.toastMessage)
    }
}

// MARK: - Friend Request Card View

struct FriendRequestCardView: View {
    let request: FriendRequestWithUser
    let requestType: FriendRequestType
    let isProcessing: Bool
    let onAccept: () -> Void
    let onReject: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            // Avatar
            AvatarView(image: nil, url: request.user.avatarUrl, size: 50)

            // User Info
            VStack(alignment: .leading, spacing: 2) {
                Text(request.user.displayName ?? request.user.username)
                    .font(Font.custom("SFProDisplay-Bold", size: 16.f))
                    .foregroundColor(.black)

                Text("@\(request.user.username)")
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))

                // Time ago
                Text(timeAgoString(from: request.createdAt))
                    .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            }

            Spacer()

            // Action Buttons
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                actionButtons
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch requestType {
        case .received:
            HStack(spacing: 8) {
                // Accept Button
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.green)
                        .clipShape(Circle())
                }

                // Reject Button
                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .clipShape(Circle())
                }
            }

        case .sent:
            // Cancel Button
            Button(action: onCancel) {
                Text("Cancel")
                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                    .cornerRadius(18)
            }
        }
    }

    // MARK: - Time Ago Helper

    private func timeAgoString(from timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hr ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Previews

#Preview("Friend Requests - Default") {
    FriendRequestsView(currentPage: .constant(.friendRequests))
}

#Preview("Friend Requests - Dark Mode") {
    FriendRequestsView(currentPage: .constant(.friendRequests))
        .preferredColorScheme(.dark)
}
