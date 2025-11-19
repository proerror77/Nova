import Foundation
import SwiftUI

// MARK: - Login View Model

@MainActor
class LoginViewModel: ObservableObject {
    @Published var isLoginMode = true
    @Published var username = ""
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authManager = AuthenticationManager.shared

    // MARK: - Actions

    func login() async {
        guard validate() else { return }

        isLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.login(
                username: username,
                password: password
            )
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func register() async {
        guard validate() else { return }

        isLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.register(
                username: username,
                email: email,
                password: password,
                displayName: displayName.isEmpty ? username : displayName
            )
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            errorMessage = "Registration failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func toggleMode() {
        isLoginMode.toggle()
        errorMessage = nil
    }

    // MARK: - Validation

    private func validate() -> Bool {
        if username.isEmpty {
            errorMessage = "Please enter a username"
            return false
        }

        if password.isEmpty {
            errorMessage = "Please enter a password"
            return false
        }

        if !isLoginMode && email.isEmpty {
            errorMessage = "Please enter an email"
            return false
        }

        if !isLoginMode && password.count < 6 {
            errorMessage = "Password must be at least 6 characters"
            return false
        }

        return true
    }
}
