import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: AuthViewModel

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
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
