import SwiftUI

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

            CreateTabView()
                .tabItem {
                    Image(systemName: "plus.square.fill")
                    Text("Create")
                }
                .tag(2)

            NotificationsTabView()
                .tabItem {
                    Image(systemName: "bell.fill")
                    Text("Notifications")
                }
                .tag(3)

            ProfileTabView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(4)
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

// MARK: - Create Tab

private struct CreateTabView: View {
    @State private var postContent = ""
    @State private var isPosting = false
    @State private var showSuccess = false
    @State private var errorMessage: String? = nil
    private let postService = PostService()

    var body: some View {
        VStack(spacing: 20) {
            Text("✏️ Create Post")
                .font(.title)
                .fontWeight(.bold)
                .padding()

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

            Spacer()
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
            _ = try await postService.createPost(caption: postContent)

            // Clear the text and show success
            postContent = ""
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
