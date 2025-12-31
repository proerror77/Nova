import SwiftUI

struct SearchView: View {
    @Binding var showSearch: Bool
    @State private var viewModel = SearchViewModel()
    @FocusState private var isSearchFocused: Bool
    @State private var showUserProfile = false
    @State private var selectedUserId: String?

    var body: some View {
        ZStack {
            // MARK: - Background
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Search Bar
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        // Search field
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15))
                                .foregroundColor(DesignTokens.textMuted)

                            TextField("Search users, posts, hashtags", text: $viewModel.searchText)
                                .font(.system(size: 15))
                                .foregroundColor(DesignTokens.textPrimary)
                                .focused($isSearchFocused)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .onChange(of: viewModel.searchText) { _, _ in
                                    viewModel.performSearch()
                                }

                            // Clear button
                            if !viewModel.searchText.isEmpty {
                                Button(action: {
                                    viewModel.searchText = ""
                                    viewModel.searchResults = []
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(DesignTokens.textMuted)
                                }
                            }
                        }
                        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .frame(height: 32)
                        .background(DesignTokens.inputBackground)
                        .cornerRadius(37)

                        // Cancel button
                        Button(action: {
                            showSearch = false
                        }) {
                            Text("Cancel")
                                .font(.system(size: 14))
                                .foregroundColor(DesignTokens.textPrimary)
                        }
                        .frame(width: 50)
                    }
                    .frame(height: DesignTokens.topBarHeight)
                    .padding(.horizontal, 16)
                    .background(DesignTokens.surface)

                    Divider()
                        .frame(height: 0.5)
                        .background(DesignTokens.borderColor)
                }

                // MARK: - Content
                ScrollView {
                    VStack(spacing: 0) {
                        if viewModel.searchText.isEmpty {
                            // Show recent searches
                            recentSearchesView
                        } else if viewModel.isSearching {
                            // Loading state
                            loadingView
                        } else if viewModel.searchResults.isEmpty {
                            // No results
                            emptyResultsView
                        } else {
                            // Search results
                            searchResultsView
                        }
                    }
                    .padding(.top, 16)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            Task {
                await viewModel.loadRecentSearches()
            }
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
            } else {
                // Fallback: auto-dismiss if userId is nil to prevent blank screen
                Color.clear
                    .onAppear {
                        showUserProfile = false
                    }
            }
        }
    }

    // MARK: - Filter Tabs
    private var filterTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SearchFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        viewModel.changeFilter(filter)
                    }) {
                        Text(filter.rawValue)
                            .font(.system(size: 14, weight: viewModel.selectedFilter == filter ? .semibold : .regular))
                            .foregroundColor(viewModel.selectedFilter == filter ? .white : DesignTokens.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.selectedFilter == filter
                                    ? Color(red: 0.87, green: 0.11, blue: 0.26)
                                    : DesignTokens.inputBackground
                            )
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(DesignTokens.surface)
    }

    // MARK: - Recent Searches
    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.recentSearches.isEmpty {
                HStack {
                    Text("Recent Searches")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    Button(action: {
                        viewModel.clearRecentSearches()
                    }) {
                        Text("Clear")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                }
                .padding(.horizontal, 16)

                ForEach(viewModel.recentSearches, id: \.self) { query in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.textMuted)

                        Text(query)
                            .font(.system(size: 15))
                            .foregroundColor(DesignTokens.textPrimary)

                        Spacer()

                        Button(action: {
                            viewModel.deleteRecentSearch(query)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textMuted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(DesignTokens.surface)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.useRecentSearch(query)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(DesignTokens.textMuted)

                    Text("Search for users, posts, or hashtags")
                        .font(.system(size: 15))
                        .foregroundColor(DesignTokens.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching...")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textSecondary)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Empty Results
    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(DesignTokens.textMuted)

            Text("No results found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignTokens.textPrimary)

            Text("Try searching for something else")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Search Results
    private var searchResultsView: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.searchResults) { result in
                searchResultRow(result)
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ result: SearchResult) -> some View {
        switch result {
        case .user(let id, let username, let displayName, let avatarUrl, let isVerified):
            UserSearchResultRow(
                id: id,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl,
                isVerified: isVerified,
                onTap: {
                    selectedUserId = id
                    showUserProfile = true
                }
            )

        case .post(let id, let content, let author, let createdAt, let likeCount):
            PostSearchResultRow(
                id: id,
                content: content,
                author: author,
                createdAt: createdAt,
                likeCount: likeCount
            )

        case .hashtag(let tag, let postCount):
            HashtagSearchResultRow(
                tag: tag,
                postCount: postCount
            )
        }
    }
}

// MARK: - User Search Result Row

struct UserSearchResultRow: View {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let isVerified: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                AvatarView(
                    image: nil,
                    url: avatarUrl,
                    size: 48,
                    backgroundColor: Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
                )

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DesignTokens.textPrimary)

                        if isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                        }
                    }

                    Text("@\(username)")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(DesignTokens.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignTokens.surface)
        }
    }
}

// MARK: - Post Search Result Row

struct PostSearchResultRow: View {
    let id: String
    let content: String
    let author: String
    let createdAt: Date
    let likeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(author)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignTokens.textPrimary)

                Spacer()

                Text(relativeTime)
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.textSecondary)
            }

            Text(content)
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textPrimary)
                .lineLimit(3)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.system(size: 12))
                    Text(likeCount.abbreviated)
                        .font(.system(size: 12))
                }
                .foregroundColor(DesignTokens.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.surface)
    }

    private var relativeTime: String {
        let interval = Date().timeIntervalSince(createdAt)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if hours < 24 {
            return "\(max(1, hours))h"
        } else {
            return "\(days)d"
        }
    }
}

// MARK: - Hashtag Search Result Row

struct HashtagSearchResultRow: View {
    let tag: String
    let postCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DesignTokens.inputBackground)
                    .frame(width: 48, height: 48)

                Text("#")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DesignTokens.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(tag)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DesignTokens.textPrimary)

                Text("\(postCount) posts")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.surface)
    }
}

#Preview {
    SearchView(showSearch: .constant(true))
}
