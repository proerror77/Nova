import SwiftUI
import PhotosUI

public struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showEnvironmentInfo = false

    public var body: some View {
        TabView(selection: $selectedTab) {
            FeedTabView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

            ExploreTabView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Explore")
                }
                .tag(1)

            MessagingTabView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Messages")
                }
                .tag(2)

            CreateTabView()
                .tabItem {
                    Image(systemName: "plus.square.fill")
                    Text("Create")
                }
                .tag(3)

            NotificationsTabView()
                .tabItem {
                    Image(systemName: "bell.fill")
                    Text("Notifications")
                }
                .tag(4)

            ProfileTabView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(5)
        }
    }

    public init() {}
}

// MARK: - Feed Tab

private struct FeedTabView: View {
    @State private var feedState: AsyncState<[Post]> = .loading
    private let feedService = FeedService()

    var body: some View {
        VStack(spacing: 16) {
            Text("🏠 Home Feed")
                .font(.title)
                .fontWeight(.bold)
                .padding()

            AsyncContentView(state: feedState) { posts in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(posts) { post in
                            FeedPostCell(post: post)
                        }
                    }
                    .padding()
                }
            } onRetry: {
                Task {
                    await loadFeed()
                }
            }
        }
        .task {
            await loadFeed()
        }
    }

    private func loadFeed() async {
        feedState = .loading
        do {
            let posts = try await feedService.getFeed()
            feedState = .success(posts)
        } catch let error as APIError {
            feedState = .error(error.localizedDescription)
        } catch {
            feedState = .error("Failed to load feed")
        }
    }
}

// MARK: - Explore Tab

private struct ExploreTabView: View {
    @State private var searchText = ""
    @State private var searchResults: AsyncState<[User]> = .idle
    @State private var searchHistory = SearchHistory.shared
    private let searchService = SearchService()

    var body: some View {
        VStack(spacing: 16) {
            Text("🔍 Explore")
                .font(.title)
                .fontWeight(.bold)
                .padding()

            SearchBar(text: $searchText, onSearch: performSearch)
                .padding()

            if searchText.isEmpty && searchResults == .idle {
                // Show search history and suggestions
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !searchHistory.history.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recent Searches")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(searchHistory.history) { entry in
                                    HStack {
                                        Button(action: {
                                            searchText = entry.query
                                        }) {
                                            HStack {
                                                Image(systemName: "clock")
                                                    .foregroundColor(.gray)
                                                Text(entry.query)
                                                    .foregroundColor(.primary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        Button(action: {
                                            searchHistory.removeEntry(id: entry.id)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray.opacity(0.5))
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical)
                }
            } else {
                AsyncContentView(state: searchResults) { users in
                    if users.isEmpty && !searchText.isEmpty {
                        Text("No results found")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            ForEach(users) { user in
                                UserSearchResultCell(user: user)
                            }
                        }
                        .padding()
                    }
                } onRetry: {
                    Task {
                        await performSearch(searchText)
                    }
                }
            }

            Spacer()
        }
        .onAppear {
            searchHistory.loadHistory()
        }
    }

    private func performSearch(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = .idle
            return
        }

        // Add to search history
        searchHistory.addQuery(query)

        searchResults = .loading
        do {
            let results = try await searchService.searchUsers(query: query)
            searchResults = .success(results)
        } catch is CancellationError {
            // Ignore cancellation triggered by rapid input changes
            return
        } catch let error as APIError {
            searchResults = .error(error.localizedDescription)
        } catch {
            searchResults = .error("Search failed")
        }
    }
}

// MARK: - Messaging Tab

private struct MessagingTabView: View {
    @State private var conversationsState: AsyncState<[Conversation]> = .loading
    @State private var selectedConversationId: String? = nil
    private let messagingService = MessagingService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("💬 Messages")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()

                AsyncContentView(state: conversationsState) { conversations in
                    if conversations.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No Conversations")
                                .font(.headline)
                            Text("Start a conversation with someone")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(conversations) { conversation in
                                    NavigationLink(value: conversation) {
                                        ConversationCell(conversation: conversation)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }
                } onRetry: {
                    Task {
                        await loadConversations()
                    }
                }
            }
            .navigationDestination(for: Conversation.self) { conversation in
                MessageDetailView(conversation: conversation)
            }
        }
        .task {
            await loadConversations()
        }
    }

    private func loadConversations() async {
        conversationsState = .loading
        do {
            let conversations = try await messagingService.getConversations()
            conversationsState = .success(conversations)
        } catch let error as APIError {
            conversationsState = .error(error.localizedDescription)
        } catch let error as MessagingError {
            conversationsState = .error(error.localizedDescription)
        } catch {
            conversationsState = .error("Failed to load conversations")
        }
    }
}

// MARK: - Messaging Components

private struct ConversationCell: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.gray)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if let lastMessageAt = conversation.lastMessageAt {
                        Text(formatTimeAgo(lastMessageAt))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                } else {
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }

            Spacer()

            if conversation.unreadCount > 0 {
                VStack {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(minWidth: 20)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())

                    Spacer()
                }
            }
        }
        .padding()
        .contentShape(Rectangle())
    }

    private func formatTimeAgo(_ dateString: String) -> String {
        // Simplified time formatting - in production, use DateFormatter
        return "Now"
    }
}

private struct MessageDetailView: View {
    let conversation: Conversation
    @State private var messageText = ""
    @State private var messagesState: AsyncState<[Message]> = .loading
    @State private var isSending = false
    private let messagingService = MessagingService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(conversation.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if conversation.isGroup {
                    Text("\(conversation.participantCount) participants")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .borderBottom()

            // Messages
            AsyncContentView(state: messagesState) { messages in
                if messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No messages yet")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                if !message.isRecalled {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.senderName)
                                            .font(.caption)
                                            .fontWeight(.semibold)

                                        Text(message.content)
                                            .font(.body)
                                            .padding(8)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    .padding(.horizontal)
                                } else {
                                    Text("Message recalled")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            } onRetry: {
                Task {
                    await loadMessages()
                }
            }

            Spacer()

            // Message input
            HStack(spacing: 8) {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty || isSending)
            }
            .padding()
            .borderTop()
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
    }

    private func loadMessages() async {
        messagesState = .loading
        do {
            let messages = try await messagingService.getMessages(conversationId: conversation.id)
            messagesState = .success(messages)
        } catch let error as APIError {
            messagesState = .error(error.localizedDescription)
        } catch let error as MessagingError {
            messagesState = .error(error.localizedDescription)
        } catch {
            messagesState = .error("Failed to load messages")
        }
    }

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }

        isSending = true
        messageText = ""

        Task {
            do {
                let _ = try await messagingService.sendMessage(
                    conversationId: conversation.id,
                    content: content
                )
                // Refresh messages
                await loadMessages()
            } catch {
                isSending = false
            }
        }
    }
}

// MARK: - Create Tab

private struct CreateTabView: View {
    @State private var postContent = ""
    @State private var isPosting = false
    @State private var showSuccess = false
    @State private var errorMessage: String? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    private let postService = PostService()

    var body: some View {
        VStack(spacing: 20) {
            Text("✏️ Create Post")
                .font(.title)
                .fontWeight(.bold)
                .padding()

            ScrollView {
                VStack(spacing: 20) {
                    // Photo picker button
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            if let selectedImage = selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 200)
                                    .clipped()
                                    .cornerRadius(8)
                                    .overlay(alignment: .topTrailing) {
                                        Button(action: { self.selectedImage = nil; selectedPhotoItem = nil }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.red)
                                                .padding(8)
                                        }
                                    }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.blue)
                                    Text("Add Photo or Video")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 2))
                            }
                        }
                        .onChange(of: selectedPhotoItem) { oldValue, newValue in
                            Task {
                                if let data = try await newValue?.loadTransferable(type: Data.self) {
                                    selectedImage = UIImage(data: data)
                                }
                            }
                        }
                    }
                    .padding()

                    // Text editor
                    TextEditor(text: $postContent)
                        .frame(minHeight: 100)
                        .border(Color.gray.opacity(0.3))
                        .padding()

                    // Character count
                    HStack {
                        Spacer()
                        Text("\(postContent.count)/\(PostService.maxCaptionLength)")
                            .font(.caption)
                            .foregroundColor(postContent.count > PostService.maxCaptionLength ? .red : .gray)
                            .padding(.horizontal)
                    }

                    // Error message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding()
                    }

                    // Success message
                    if showSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Post created successfully!")
                                .foregroundColor(.green)
                                .font(.caption)
                            Spacer()
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .padding()
                    }

                    Button(action: {
                        Task {
                            await createPost()
                        }
                    }) {
                        if isPosting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Post")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(postContent.isEmpty || isPosting ? Color.blue.opacity(0.5) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(postContent.isEmpty || isPosting || postContent.count > PostService.maxCaptionLength)
                    .padding()
                }
            }
        }
    }

    private func createPost() async {
        guard !postContent.isEmpty else {
            errorMessage = PostCreationError.emptyCaption.localizedDescription
            return
        }

        guard postContent.count <= PostService.maxCaptionLength else {
            errorMessage = PostCreationError.tooLongCaption.localizedDescription
            return
        }

        isPosting = true
        errorMessage = nil
        showSuccess = false

        do {
            // For now, we'll pass a placeholder URL if image is selected
            // TODO: Implement actual image upload to backend
            let imageUrl = selectedImage != nil ? "image://\(UUID().uuidString)" : nil
            _ = try await postService.createPost(caption: postContent, imageUrl: imageUrl)

            // Clear the text and show success
            postContent = ""
            selectedImage = nil
            selectedPhotoItem = nil
            showSuccess = true

            // Hide success message after 2 seconds
            try await Task.sleep(for: .seconds(2))
            showSuccess = false
        } catch let error as PostCreationError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to create post. Please try again."
        }

        isPosting = false
    }
}

// MARK: - Notifications Tab

private struct NotificationsTabView: View {
    @State private var notificationState: AsyncState<[Notification]> = .loading
    private let notificationService = NotificationService()

    var body: some View {
        VStack(spacing: 16) {
            Text("🔔 Notifications")
                .font(.title)
                .fontWeight(.bold)
                .padding()

            AsyncContentView(state: notificationState) { notifications in
                List {
                    ForEach(notifications) { notification in
                        NotificationCell(notification: notification)
                    }
                }
            } onRetry: {
                Task {
                    await loadNotifications()
                }
            }
        }
        .task {
            await loadNotifications()
        }
    }

    private func loadNotifications() async {
        notificationState = .loading
        do {
            let notifications = try await notificationService.getNotifications()
            notificationState = .success(notifications)
        } catch let error as APIError {
            notificationState = .error(error.localizedDescription)
        } catch {
            notificationState = .error("Failed to load notifications")
        }
    }
}

// MARK: - Profile Tab

private struct ProfileTabView: View {
    @State private var profileState: AsyncState<User> = .loading
    private let userService = UserService()

    var body: some View {
        VStack(spacing: 16) {
            Text("👤 Profile")
                .font(.title)
                .fontWeight(.bold)
                .padding()

            AsyncContentView(state: profileState) { user in
                VStack(spacing: 12) {
                    KFImageView(url: URL(string: user.avatarUrl ?? ""))
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())

                    VStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.headline)
                        Text("@\(user.username)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    if let bio = user.bio {
                        Text(bio)
                            .font(.body)
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                    }

                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("\(user.postsCount)")
                                .font(.headline)
                            Text("Posts")
                                .font(.caption)
                        }

                        VStack(spacing: 4) {
                            Text("\(formatCount(user.followersCount))")
                                .font(.headline)
                            Text("Followers")
                                .font(.caption)
                        }

                        VStack(spacing: 4) {
                            Text("\(formatCount(user.followingCount))")
                                .font(.headline)
                            Text("Following")
                                .font(.caption)
                        }
                    }
                    .padding()
                }
                .padding()

                Button(action: {}) {
                    Text("Edit Profile")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                .padding()

                Spacer()
            } onRetry: {
                Task {
                    await loadProfile()
                }
            }
        }
        .task {
            await loadProfile()
        }
    }

    private func loadProfile() async {
        profileState = .loading
        do {
            let user = try await userService.getCurrentUser()
            profileState = .success(user)
        } catch let error as APIError {
            profileState = .error(error.localizedDescription)
        } catch {
            profileState = .error("Failed to load profile")
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000).replacingOccurrences(of: ".0K", with: "K")
        }
        return "\(count)"
    }
}

// MARK: - Helper Components

private enum AsyncState<T>: Equatable where T: Equatable {
    case idle
    case loading
    case success(T)
    case error(String)

    static func == (lhs: AsyncState<T>, rhs: AsyncState<T>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            return true
        case let (.success(l), .success(r)):
            return l == r
        case let (.error(l), .error(r)):
            return l == r
        default:
            return false
        }
    }
}

private struct AsyncContentView<T: Equatable, Content: View>: View {
    let state: AsyncState<T>
    @ViewBuilder let content: (T) -> Content
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .success(let data):
            content(data)
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                Text("Error")
                    .font(.headline)
                Text(message)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.headline)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var onSearch: (String) async -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search", text: $text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { newValue in
                    Task {
                        await onSearch(newValue)
                    }
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

private struct FeedPostCell: View {
    let post: Post
    @State private var isLiked: Bool = false
    @State private var likeCount: Int = 0
    private let interactionService = PostInteractionService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                KFImageView(url: URL(string: post.author.avatarUrl ?? ""))
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayName)
                        .font(.headline)
                    Text(post.createdAt)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()
            }

            Text(post.caption)
                .font(.body)
                .lineLimit(3)

            HStack(spacing: 20) {
                Button(action: {
                    Task {
                        await toggleLike()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                        Text("\(likeCount)")
                            .font(.caption)
                    }
                    .foregroundColor(isLiked ? .red : .gray)
                }

                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        Text("\(post.commentCount)")
                            .font(.caption)
                    }
                }

                Button(action: {
                    Task {
                        try? await interactionService.sharePost(postId: post.id)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.right")
                        Text("\(interactionService.getShareCount(postId: post.id))")
                            .font(.caption)
                    }
                }

                Spacer()
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .onAppear {
            isLiked = interactionService.isPostLiked(postId: post.id)
            likeCount = post.likeCount
        }
    }

    private func toggleLike() async {
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1

        if isLiked {
            try? await interactionService.likePost(postId: post.id)
        } else {
            try? await interactionService.unlikePost(postId: post.id)
        }
    }
}

private struct NotificationCell: View {
    let notification: Notification

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)

            VStack(alignment: .leading) {
                Text("\(notification.actor.displayName) liked your post")
                    .font(.body)
                Text(notification.timestamp)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
    }
}

private struct UserSearchResultCell: View {
    let user: User

    var body: some View {
        VStack(spacing: 8) {
            KFImageView(url: URL(string: user.avatarUrl ?? ""))
                .frame(width: 50, height: 50)
                .clipShape(Circle())

            Text(user.displayName)
                .font(.headline)
                .lineLimit(1)

            Text("@\(user.username)")
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)

            Text("\(user.followersCount) followers")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
