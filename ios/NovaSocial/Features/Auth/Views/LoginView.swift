import SwiftUI

// MARK: - Login View

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo/Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.blue)

                        Text(viewModel.isLoginMode ? "Welcome Back" : "Create Account")
                            .font(.title)
                            .fontWeight(.bold)

                        Text(viewModel.isLoginMode ? "Sign in to continue" : "Join Nova Social")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)

                    // Form Fields
                    VStack(spacing: 16) {
                        // Username
                        TextField("Username", text: $viewModel.username)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        // Email (Register only)
                        if !viewModel.isLoginMode {
                            TextField("Email", text: $viewModel.email)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                        }

                        // Password
                        SecureField("Password", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)

                        // Display Name (Register only)
                        if !viewModel.isLoginMode {
                            TextField("Display Name (optional)", text: $viewModel.displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.horizontal)

                    // Error Message
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Action Button
                    Button(action: {
                        Task {
                            if viewModel.isLoginMode {
                                await viewModel.login()
                            } else {
                                await viewModel.register()
                            }
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(viewModel.isLoginMode ? "Sign In" : "Create Account")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isLoading)
                    .padding(.horizontal)

                    // Toggle Mode
                    Button(action: {
                        viewModel.toggleMode()
                    }) {
                        HStack(spacing: 4) {
                            Text(viewModel.isLoginMode ? "Don't have an account?" : "Already have an account?")
                                .foregroundColor(.gray)
                            Text(viewModel.isLoginMode ? "Sign Up" : "Sign In")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 40)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
}
