import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: AuthViewModel

    init() {
        _viewModel = StateObject(wrappedValue: AuthViewModel(appState: AppState()))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Username Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    TextField("Choose a username", text: $viewModel.username)
                        .textFieldStyle(RoundedTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                // Email Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    TextField("Enter your email", text: $viewModel.email)
                        .textFieldStyle(RoundedTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                }

                // Password Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    SecureField("Create a password", text: $viewModel.password)
                        .textFieldStyle(RoundedTextFieldStyle())

                    Text("Minimum 8 characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Confirm Password Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    SecureField("Re-enter your password", text: $viewModel.confirmPassword)
                        .textFieldStyle(RoundedTextFieldStyle())

                    if !viewModel.password.isEmpty && !viewModel.confirmPassword.isEmpty {
                        if viewModel.password == viewModel.confirmPassword {
                            Label("Passwords match", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Label("Passwords don't match", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Register Button
                Button {
                    Task {
                        await viewModel.register()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Create Account")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.isRegisterValid || viewModel.isLoading)

                // Terms
                Text("By signing up, you agree to our Terms of Service and Privacy Policy")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    ErrorMessageView(message: errorMessage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
        .onAppear {
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
    RegisterView()
        .environmentObject(AppState())
}
