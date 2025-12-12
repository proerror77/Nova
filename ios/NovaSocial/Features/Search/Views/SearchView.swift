import SwiftUI

struct SearchView: View {
    @Binding var showSearch: Bool
    @State private var viewModel = SearchViewModel()
    @FocusState private var isSearchFocused: Bool

    // User profile navigation state
    @State private var showUserProfile = false
    @State private var selectedUserId: String?

    var body: some View {
        ZStack {
            // MARK: - 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部搜索区域
                VStack(spacing: 0) {
                    // 搜索栏和取消按钮
                    HStack(spacing: 10) {
                        // 搜索框
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15))
                                .foregroundColor(DesignTokens.textMuted)

                            TextField("Search", text: $viewModel.searchText)
                                .font(.system(size: 15))
                                .foregroundColor(DesignTokens.textPrimary)
                                .focused($isSearchFocused)
                                .onChange(of: viewModel.searchText) { _, _ in
                                    viewModel.performSearch()
                                }
                            
                            if viewModel.isSearching {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if !viewModel.searchText.isEmpty {
                                Button(action: {
                                    viewModel.searchText = ""
                                    viewModel.searchResults = []
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.textMuted)
                                }
                            }
                        }
                        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .frame(height: 32)
                        .background(DesignTokens.inputBackground)
                        .cornerRadius(37)

                        // 取消按钮
                        Button(action: {
                            showSearch = false
                        }) {
                            Text("Cancel")
                                .font(.system(size: 14))
                                .foregroundColor(DesignTokens.textPrimary)
                        }
                        .frame(width: 44)
                    }
                    .frame(height: DesignTokens.topBarHeight)
                    .padding(.horizontal, 16)
                    .background(DesignTokens.surface)

                    // 分隔线
                    Divider()
                        .frame(height: 0.5)
                        .background(DesignTokens.borderColor)
                }

                // MARK: - 搜索结果区域
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.searchText.isEmpty {
                            // 显示最近搜索
                            if !viewModel.recentSearches.isEmpty {
                                recentSearchesSection
                            } else if !viewModel.isLoadingRecent {
                                // 空状态
                                emptyStateView
                            }
                        } else if viewModel.searchResults.isEmpty && !viewModel.isSearching {
                            // 无结果
                            noResultsView
                        } else {
                            // 搜索结果
                            ForEach(viewModel.searchResults) { result in
                                SearchResultItem(result: result)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleResultTap(result)
                                    }
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            
            // Error message
            if let errorMessage = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            // 自动聚焦搜索框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .task {
            await viewModel.loadRecentSearches()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
            }
        }
    }

    // MARK: - Handle Result Tap
    private func handleResultTap(_ result: SearchResult) {
        switch result {
        case .user(let id, let username, _, _, _):
            // Save to recent searches
            viewModel.saveToRecentSearches(username)
            // Navigate to user profile
            selectedUserId = id
            showUserProfile = true

        case .post(let id, _, _, _, _):
            // TODO: Navigate to post detail
            print("Navigate to post: \(id)")

        case .hashtag(let tag, _):
            // TODO: Navigate to hashtag feed
            print("Navigate to hashtag: \(tag)")
        }
    }
    
    // MARK: - Recent Searches Section
    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Searches")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DesignTokens.textPrimary)
                
                Spacer()
                
                Button(action: {
                    viewModel.clearRecentSearches()
                }) {
                    Text("Clear")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            ForEach(viewModel.recentSearches, id: \.self) { query in
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
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
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.useRecentSearch(query)
                }
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(DesignTokens.textMuted)
            
            Text("Search for users")
                .font(.system(size: 15))
                .foregroundColor(DesignTokens.textMuted)
        }
        .padding(.top, 100)
    }
    
    // MARK: - No Results View
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(DesignTokens.textMuted)
            
            Text("No results found for \"\(viewModel.searchText)\"")
                .font(.system(size: 15))
                .foregroundColor(DesignTokens.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 100)
        .padding(.horizontal, 32)
    }
}

// MARK: - 搜索结果项组件（占位）
struct SearchResultItem: View {
    let result: SearchResult
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标/头像
            resultIcon
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(resultTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DesignTokens.textPrimary)
                    .lineLimit(1)

                Text(resultSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
            
            // 右侧指示器
            resultAccessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.surface)
    }
    
    @ViewBuilder
    private var resultIcon: some View {
        switch result {
        case .user(_, _, _, let avatarUrl, let isVerified):
            ZStack(alignment: .bottomTrailing) {
                if let avatarUrl = avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .frame(width: 44, height: 44)
                }
                
                if isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .background(Circle().fill(Color.white).frame(width: 14, height: 14))
                }
            }
            
        case .post:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.91, green: 0.91, blue: 0.91))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 18))
                        .foregroundColor(DesignTokens.textMuted)
                )
            
        case .hashtag:
            Circle()
                .fill(Color(red: 0.87, green: 0.11, blue: 0.26).opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text("#")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                )
        }
    }
    
    private var resultTitle: String {
        switch result {
        case .user(_, let username, let displayName, _, _):
            return displayName.isEmpty ? username : displayName
        case .post(_, let content, _, _, _):
            return content.prefix(50).description + (content.count > 50 ? "..." : "")
        case .hashtag(let tag, _):
            return "#\(tag)"
        }
    }
    
    private var resultSubtitle: String {
        switch result {
        case .user(_, let username, let displayName, _, _):
            return displayName.isEmpty ? "" : "@\(username)"
        case .post(_, _, let author, let createdAt, _):
            return "by @\(author) • \(formatDate(createdAt))"
        case .hashtag(_, let postCount):
            return "\(formatCount(postCount)) posts"
        }
    }
    
    @ViewBuilder
    private var resultAccessory: some View {
        switch result {
        case .user:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.textMuted)
        case .post(_, _, _, _, let likeCount):
            HStack(spacing: 4) {
                Image(systemName: "heart")
                    .font(.system(size: 12))
                Text("\(likeCount)")
                    .font(.system(size: 12))
            }
            .foregroundColor(DesignTokens.textMuted)
        case .hashtag:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignTokens.textMuted)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    SearchView(showSearch: .constant(true))
}
