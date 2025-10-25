import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: AuthViewModel
    private let appleService = AppleSignInService()
    private let googleService = GoogleSignInService()

    init() {
        // Note: We'll inject appState in the initializer later
        _viewModel = StateObject(wrappedValue: AuthViewModel(appState: AppState()))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Email Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .accessibleCaption()
                        .fontWeight(.semibold)

                    TextField("Enter your email", text: $viewModel.email)
                        .textFieldStyle(RoundedTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .voiceOverSupport(
                            label: "邮箱地址",
                            hint: "请输入您的邮箱地址",
                            value: viewModel.email.isEmpty ? "未填写" : viewModel.email
                        )
                        .minTouchTarget(height: 44)
                }

                // Password Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .accessibleCaption()
                        .fontWeight(.semibold)

                    SecureField("Enter your password", text: $viewModel.password)
                        .textFieldStyle(RoundedTextFieldStyle())
                        .voiceOverSupport(
                            label: "密码",
                            hint: "请输入您的密码",
                            value: viewModel.password.isEmpty ? "未填写" : "已输入"
                        )
                        .minTouchTarget(height: 44)
                }

                // Forgot Password
                HStack {
                    Spacer()
                    Button("Forgot Password?") {
                        // TODO: Navigate to forgot password
                    }
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .voiceOverSupport(
                        label: "忘记密码",
                        hint: "双击重置密码",
                        traits: .isButton
                    )
                    .minTouchTarget()
                }

                // Login Button
                Button {
                    Task {
                        await viewModel.login()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Login")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.isLoginValid || viewModel.isLoading)
                .voiceOverSupport(
                    label: viewModel.isLoading ? "正在登录" : "登录",
                    hint: viewModel.isLoginValid ? "双击登录" : "请填写完整信息",
                    traits: .isButton
                )
                .minTouchTarget(height: 48)

                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    ErrorMessageView(message: errorMessage)
                }

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                    Text("Or continue with").font(.footnote).foregroundColor(.secondary)
                    Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                }

                // Social Login Buttons
                VStack(spacing: 12) {
                    // Sign in with Apple
                    Button(action: handleAppleSignIn) {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("Sign in with Apple").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .minTouchTarget(height: 48)
                    .accessibilityLabel("使用 Apple 登录")

                    // Google Sign-In
                    Button(action: handleGoogleSignIn) {
                        HStack {
                            Image(systemName: "g.circle.fill")
                            Text("Sign in with Google").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .minTouchTarget(height: 48)
                    .accessibilityLabel("使用 Google 登录")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
        .onAppear {
            // Inject appState when view appears
            viewModel.appState.isAuthenticated = appState.isAuthenticated
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Social Sign-In Actions
    private func handleAppleSignIn() {
        appleService.signIn { result in
            switch result {
            case .success(let payload):
                Task { await exchangeOAuthCode(provider: "apple", code: payload.code, state: payload.state) }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
    }

    private func handleGoogleSignIn() {
        // Launch OAuth consent. Deep link handler will process the callback.
        googleService.start { result in
            if case .failure(let error) = result {
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
    }

    // MARK: - Exchange code → tokens via backend
    private func exchangeOAuthCode(provider: String, code: String, state: String) async {
        struct OAuthAuthorizeRequest: Encodable { let provider, code, state, redirectUri: String }
        struct OAuthAuthorizeResponse: Decodable {
            let accessToken: String, refreshToken: String, tokenType: String, expiresIn: Int, userId: String, email: String
            enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", tokenType = "token_type", expiresIn = "expires_in", userId = "user_id", email }
        }

        let api = APIClient(baseURL: AppConfig.baseURL)
        let req = OAuthAuthorizeRequest(provider: provider, code: code, state: state, redirectUri: "novasocial://auth/oauth/\(provider)")
        let endpoint = APIEndpoint(path: "/auth/oauth/authorize", method: .post, body: req)
        do {
            let resp: OAuthAuthorizeResponse = try await api.request(endpoint, authenticated: false)
            let userId = UUID(uuidString: resp.userId) ?? UUID()
            let username = resp.email.split(separator: "@").first.map(String.init) ?? "user"
            let user = User(id: userId, username: username, email: resp.email, displayName: nil, bio: nil, avatarUrl: nil, isVerified: false, createdAt: Date())
            let tokens = AuthTokens(accessToken: resp.accessToken, refreshToken: resp.refreshToken, expiresIn: resp.expiresIn, tokenType: resp.tokenType)
            AuthManager.shared.saveAuth(user: user, tokens: tokens)
            await MainActor.run { appState.isAuthenticated = true }
            OAuthStateManager.shared.clearState(); OAuthStateManager.shared.clearNonce()
        } catch {
            await MainActor.run {
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
