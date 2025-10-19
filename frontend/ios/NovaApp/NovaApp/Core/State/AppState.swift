import Foundation
import SwiftUI

/// Global application state manager
/// Manages app-wide state including auth, theme, network status
@MainActor
class AppState: ObservableObject {
    // MARK: - Singleton
    static let shared = AppState()

    // MARK: - Published State
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    @Published var colorScheme: ColorScheme? = nil
    @Published var isOffline: Bool = false
    @Published var networkQuality: NetworkQuality = .good

    // MARK: - Services
    let authService: AuthService
    let networkMonitor: NetworkMonitor

    private init() {
        self.authService = AuthService.shared
        self.networkMonitor = NetworkMonitor.shared

        // Observe auth changes
        setupAuthObserver()
        setupNetworkObserver()
    }

    // MARK: - Setup Observers
    private func setupAuthObserver() {
        // Mirror auth state
        authService.$isAuthenticated
            .assign(to: &$isAuthenticated)

        authService.$currentUser
            .assign(to: &$currentUser)
    }

    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .map { !$0 }
            .assign(to: &$isOffline)

        networkMonitor.$quality
            .assign(to: &$networkQuality)
    }

    // MARK: - Theme Management
    func setColorScheme(_ scheme: ColorScheme?) {
        colorScheme = scheme
        UserDefaults.standard.set(
            scheme == .dark ? "dark" : scheme == .light ? "light" : "system",
            forKey: "colorScheme"
        )
    }

    func loadColorScheme() {
        let stored = UserDefaults.standard.string(forKey: "colorScheme") ?? "system"
        switch stored {
        case "dark": colorScheme = .dark
        case "light": colorScheme = .light
        default: colorScheme = nil
        }
    }
}

// MARK: - Network Quality
enum NetworkQuality {
    case excellent  // WiFi, 5G
    case good       // 4G
    case poor       // 3G or slower
    case none       // Offline
}
