import Foundation

// MARK: - Matrix Token Refresh Manager
//
// Manages Matrix token lifecycle with proactive and reactive refresh strategies:
// - Proactive: Timer-based refresh 10 minutes before expiry
// - Reactive: On-demand refresh when 401/M_UNKNOWN_TOKEN errors occur
//
// Thread Safety:
// - Uses actor isolation to prevent concurrent refresh attempts
// - Singleton accessed via .shared

@MainActor
@Observable
final class MatrixTokenRefreshManager {

    // MARK: - Singleton

    static let shared = MatrixTokenRefreshManager()

    // MARK: - Configuration

    /// Buffer time before expiry to trigger proactive refresh (10 minutes)
    private let refreshBufferSeconds: Int64 = 600

    /// Minimum interval between refresh attempts (30 seconds)
    private let minRefreshIntervalSeconds: TimeInterval = 30

    // MARK: - State

    /// Whether a refresh is currently in progress
    private(set) var isRefreshing = false

    /// Last successful refresh timestamp
    private(set) var lastRefreshTime: Date?

    /// Current token expiry time (if known)
    private(set) var tokenExpiresAt: Date?

    /// Proactive refresh timer
    private var refreshTimer: Timer?

    // MARK: - Dependencies

    private var bridgeService: MatrixBridgeService { MatrixBridgeService.shared }
    private var matrixService: MatrixService { MatrixService.shared }
    private let apiClient = APIClient.shared

    // MARK: - Initialization

    private init() {
        #if DEBUG
        print("[MatrixTokenRefresh] Manager initialized")
        #endif
    }

    // MARK: - Public API

    /// Start proactive token refresh based on expiry time
    /// - Parameter expiresAt: Token expiry timestamp (Unix seconds)
    func startProactiveRefresh(tokenExpiresAt: Int64) {
        let expiryDate = Date(timeIntervalSince1970: TimeInterval(tokenExpiresAt))
        self.tokenExpiresAt = expiryDate

        // Cancel any existing timer
        refreshTimer?.invalidate()
        refreshTimer = nil

        // Calculate when to refresh (10 minutes before expiry)
        let currentTime = Date()
        let refreshTime = expiryDate.addingTimeInterval(-TimeInterval(refreshBufferSeconds))

        // If already past refresh time, refresh immediately
        if refreshTime <= currentTime {
            #if DEBUG
            print("[MatrixTokenRefresh] Token already expired or expiring soon, refreshing immediately")
            #endif
            Task {
                _ = await performRefresh()
            }
            return
        }

        // Schedule proactive refresh
        let interval = refreshTime.timeIntervalSince(currentTime)

        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("[MatrixTokenRefresh] Scheduling proactive refresh:")
        print("  - Token expires at: \(formatter.string(from: expiryDate))")
        print("  - Refresh scheduled for: \(formatter.string(from: refreshTime))")
        print("  - Time until refresh: \(Int(interval)) seconds (\(Int(interval/60)) minutes)")
        #endif

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                #if DEBUG
                print("[MatrixTokenRefresh] Proactive refresh timer fired")
                #endif
                _ = await self?.performRefresh()
            }
        }
    }

    /// Stop proactive refresh timer
    func stopProactiveRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        tokenExpiresAt = nil

        #if DEBUG
        print("[MatrixTokenRefresh] Proactive refresh stopped")
        #endif
    }

    /// Perform token refresh
    /// - Returns: true if refresh was successful, false otherwise
    @discardableResult
    func performRefresh() async -> Bool {
        // Prevent concurrent refresh attempts
        guard !isRefreshing else {
            #if DEBUG
            print("[MatrixTokenRefresh] Refresh already in progress, skipping")
            #endif
            return false
        }

        // Enforce minimum interval between refreshes
        if let lastRefresh = lastRefreshTime {
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < minRefreshIntervalSeconds {
                #if DEBUG
                print("[MatrixTokenRefresh] Too soon since last refresh (\(Int(timeSinceLastRefresh))s), skipping")
                #endif
                return false
            }
        }

        isRefreshing = true
        defer { isRefreshing = false }

        #if DEBUG
        print("[MatrixTokenRefresh] Starting token refresh...")
        #endif

        do {
            // Get fresh credentials from backend
            guard let currentUser = AuthenticationManager.shared.currentUser else {
                #if DEBUG
                print("[MatrixTokenRefresh] No current user, cannot refresh")
                #endif
                return false
            }

            let credentials = try await bridgeService.getMatrixCredentials(novaUserId: currentUser.id)

            #if DEBUG
            print("[MatrixTokenRefresh] Got new credentials:")
            print("  - Matrix User ID: \(credentials.matrixUserId)")
            print("  - Device ID: \(credentials.deviceId)")
            if let expiresAt = credentials.expiresAt {
                let expiryDate = Date(timeIntervalSince1970: TimeInterval(expiresAt))
                print("  - Expires at: \(expiryDate)")
            }
            #endif

            // Store new credentials
            matrixService.storeCredentials(
                userId: credentials.matrixUserId,
                accessToken: credentials.accessToken,
                deviceId: credentials.deviceId,
                homeserverUrl: credentials.homeserverUrl,
                expiresAt: credentials.expiresAt
            )

            // Reinitialize Matrix session with new token
            // Note: This will restart sync with the new credentials
            try await matrixService.reinitializeSession(
                accessToken: credentials.accessToken,
                deviceId: credentials.deviceId
            )

            lastRefreshTime = Date()

            // Schedule next proactive refresh if we have expiry info
            if let expiresAt = credentials.expiresAt {
                startProactiveRefresh(tokenExpiresAt: expiresAt)
            }

            #if DEBUG
            print("[MatrixTokenRefresh] Token refresh successful")
            #endif

            return true

        } catch {
            #if DEBUG
            print("[MatrixTokenRefresh] Token refresh failed: \(error)")
            #endif
            return false
        }
    }

    /// Handle a token error (reactive refresh)
    /// Call this when you receive a 401/M_UNKNOWN_TOKEN error
    /// - Parameter error: The error that occurred
    /// - Returns: true if error was a token error and refresh was attempted
    func handleTokenError(_ error: Error) async -> Bool {
        let errorString = String(describing: error)
        let isTokenError = errorString.contains("unknownToken") ||
                          errorString.contains("M_UNKNOWN_TOKEN") ||
                          errorString.contains("Access token has expired")

        guard isTokenError else {
            return false
        }

        #if DEBUG
        print("[MatrixTokenRefresh] Token error detected, attempting reactive refresh...")
        #endif

        // Clear the invalid session first
        bridgeService.clearSessionData()

        // Attempt refresh
        return await performRefresh()
    }

    /// Check if token is expired or expiring soon
    var isTokenExpiredOrExpiringSoon: Bool {
        guard let expiresAt = tokenExpiresAt else { return false }
        let bufferDate = expiresAt.addingTimeInterval(-TimeInterval(refreshBufferSeconds))
        return Date() >= bufferDate
    }

    /// Time remaining until token expires (nil if unknown)
    var timeUntilExpiry: TimeInterval? {
        guard let expiresAt = tokenExpiresAt else { return nil }
        return expiresAt.timeIntervalSince(Date())
    }
}
