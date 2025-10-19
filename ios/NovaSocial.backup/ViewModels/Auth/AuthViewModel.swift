import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var email = ""
    @Published var password = ""
    @Published var username = ""
    @Published var confirmPassword = ""

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Dependencies
    private let authRepository: AuthRepository
    private let appState: AppState

    // MARK: - Validation
    var isLoginValid: Bool {
        !email.isEmpty && !password.isEmpty
    }

    var isRegisterValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !username.isEmpty &&
        password == confirmPassword &&
        password.count >= 8
    }

    // MARK: - Initialization
    init(authRepository: AuthRepository = AuthRepository(), appState: AppState) {
        self.authRepository = authRepository
        self.appState = appState
    }

    // MARK: - Public Methods

    func login() async {
        guard isLoginValid else {
            showErrorMessage("Please fill in all fields")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let (user, _) = try await authRepository.login(
                email: email,
                password: password
            )

            appState.isAuthenticated = true
            appState.currentUser = user
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isLoading = false
    }

    func register() async {
        guard isRegisterValid else {
            showErrorMessage("Please check all fields")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let (user, _) = try await authRepository.register(
                email: email,
                username: username,
                password: password
            )

            appState.isAuthenticated = true
            appState.currentUser = user
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isLoading = false
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
