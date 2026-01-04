import SwiftUI

// MARK: - Message Search View

/// View for searching messages within a conversation
struct MessageSearchView: View {
    // MARK: - Properties

    @Binding var isPresented: Bool
    let conversationId: String
    let onMessageSelected: (Message) -> Void

    @State private var searchQuery = ""
    @State private var searchResults: [Message] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let chatService = ChatService.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    searchBar

                    Divider()
                        .background(DesignTokens.borderColor)

                    // Results
                    if isSearching {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if searchResults.isEmpty && !searchQuery.isEmpty {
                        emptyResultsView
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Search Messages")
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
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                .foregroundColor(DesignTokens.textSecondary)

            TextField("Search messages...", text: $searchQuery)
                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                .foregroundColor(DesignTokens.textPrimary)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit {
                    performSearch()
                }
                .onChange(of: searchQuery) { _, newValue in
                    // Debounced search
                    if newValue.count >= 2 {
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                            if searchQuery == newValue { // Only search if query hasn't changed
                                performSearch()
                            }
                        }
                    } else if newValue.isEmpty {
                        searchResults = []
                    }
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(DesignTokens.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.surface)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { message in
                    Button(action: {
                        onMessageSelected(message)
                        isPresented = false
                    }) {
                        MessageSearchResultRow(
                            message: message,
                            searchQuery: searchQuery
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 56)
                        .background(DesignTokens.borderColor)
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching...")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(DesignTokens.textSecondary)
            Spacer()
        }
    }

    // MARK: - Empty Results View

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(Font.custom("SFProDisplay-Regular", size: 48.f))
                .foregroundColor(DesignTokens.textSecondary.opacity(0.5))
            Text("No messages found")
                .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                .foregroundColor(DesignTokens.textPrimary)
            Text("Try a different search term")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(DesignTokens.textSecondary)
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(Font.custom("SFProDisplay-Regular", size: 40.f))
                .foregroundColor(DesignTokens.accentColor)
            Text(error)
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                performSearch()
            }
            .foregroundColor(DesignTokens.accentColor)
            Spacer()
        }
        .padding()
    }

    // MARK: - Search Logic

    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        isSearching = true
        errorMessage = nil

        Task {
            do {
                let results = try await chatService.searchMessages(
                    query: searchQuery,
                    conversationId: conversationId,
                    limit: 50
                )
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Search failed. Please try again."
                    isSearching = false
                    #if DEBUG
                    print("[MessageSearchView] Search error: \(error)")
                    #endif
                }
            }
        }
    }
}

// MARK: - Search Result Row

private struct MessageSearchResultRow: View {
    let message: Message
    let searchQuery: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Sender avatar placeholder
            Circle()
                .fill(DesignTokens.accentColor.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(message.senderId.prefix(1)).uppercased())
                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                        .foregroundColor(DesignTokens.accentColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Sender and date
                HStack {
                    Text(message.senderId)
                        .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                        .foregroundColor(DesignTokens.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(formatDate(message.createdAt))
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                // Message content with highlighted query
                highlightedText(message.content, query: searchQuery)
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(DesignTokens.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()

        guard let range = lowercaseText.range(of: lowercaseQuery) else {
            return Text(text)
        }

        let beforeMatch = String(text[text.startIndex..<range.lowerBound])
        let match = String(text[range.lowerBound..<range.upperBound])
        let afterMatch = String(text[range.upperBound..<text.endIndex])

        return Text(beforeMatch) +
            Text(match).foregroundColor(DesignTokens.accentColor).bold() +
            Text(afterMatch)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview {
    MessageSearchView(
        isPresented: .constant(true),
        conversationId: "test-conversation",
        onMessageSelected: { _ in }
    )
}
