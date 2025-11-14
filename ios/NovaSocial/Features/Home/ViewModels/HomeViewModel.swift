import Foundation
import SwiftUI

// MARK: - Home View Model

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedTab: HomeTab = .feed
    @Published var navigationState: HomeNavigationState?
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Services

    private let contentService = ContentService()
    private let socialService = SocialService()

    // MARK: - Enums

    enum HomeTab {
        case feed
        case explore
        case trending
    }

    enum HomeNavigationState {
        case newPost
        case search
        case notification
        case report
        case thankYou
    }

    // MARK: - Lifecycle

    func loadFeed() async {
        isLoading = true
        errorMessage = nil

        // TODO: Implement feed loading from backend

        isLoading = false
    }

    // MARK: - Actions

    func showNewPost() {
        navigationState = .newPost
    }

    func showSearch() {
        navigationState = .search
    }

    func showNotifications() {
        navigationState = .notification
    }

    func dismissNavigation() {
        navigationState = nil
    }
}
