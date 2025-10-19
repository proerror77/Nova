import Foundation
import Combine

/// Base ViewModel with common state management patterns
@MainActor
class BaseViewModel: ObservableObject {
    // MARK: - Loading State
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false

    // MARK: - Error Handling
    @Published var error: Error?
    @Published var showError: Bool = false

    // MARK: - Network State
    @Published var isOffline: Bool = false

    // MARK: - Lifecycle
    var cancellables = Set<AnyCancellable>()

    init() {
        observeNetworkState()
    }

    // MARK: - Error Handling
    func handleError(_ error: Error) {
        self.error = error
        self.showError = true
        print("⚠️ ViewModel Error: \(error.localizedDescription)")
    }

    func clearError() {
        self.error = nil
        self.showError = false
    }

    // MARK: - Loading State Management
    func withLoading<T>(_ operation: () async throws -> T) async throws -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }

    func withLoadingMore<T>(_ operation: () async throws -> T) async throws -> T {
        isLoadingMore = true
        defer { isLoadingMore = false }
        return try await operation()
    }

    // MARK: - Network Monitoring
    private func observeNetworkState() {
        NetworkMonitor.shared.$isConnected
            .map { !$0 }
            .assign(to: &$isOffline)
    }
}

// MARK: - Paginated ViewModel Protocol
@MainActor
protocol PaginatedViewModel: AnyObject {
    var currentPage: Int { get set }
    var hasMore: Bool { get set }
    var pageSize: Int { get }

    func loadInitial() async
    func loadMore() async
    func refresh() async
}

extension PaginatedViewModel where Self: BaseViewModel {
    func resetPagination() {
        currentPage = 0
        hasMore = true
    }
}
