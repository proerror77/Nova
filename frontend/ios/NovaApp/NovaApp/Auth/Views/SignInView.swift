import SwiftUI

/// A01 - Sign In Screen
struct SignInView: View {
    @EnvironmentObject var authService: AuthService
    let onSignUpTap: () -> Void
    let onAppleSignInTap: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Logo
                Image(systemName: "photo.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Theme.Colors.primary)
                    .padding(.top, Theme.Spacing.xxl)

                Text("Welcome Back")
                    .font(Theme.Typography.h1)
                    .foregroundColor(Theme.Colors.textPrimary)

                // Form
                VStack(spacing: Theme.Spacing.md) {
                    NovaTextField(
                        placeholder: "Email",
                        text: $email,
                        icon: "envelope",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )

                    NovaTextField(
                        placeholder: "Password",
                        text: $password,
                        icon: "lock",
                        isSecure: true,
                        errorMessage: errorMessage
                    )

                    PrimaryButton(
                        title: "Sign In",
                        action: handleSignIn,
                        isLoading: isLoading
                    )
                }
                .padding(.horizontal, Theme.Spacing.lg)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Theme.Colors.divider)
                        .frame(height: 1)
                    Text("OR")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Rectangle()
                        .fill(Theme.Colors.divider)
                        .frame(height: 1)
                }
                .padding(.horizontal, Theme.Spacing.lg)

                // Apple Sign In
                Button(action: onAppleSignInTap) {
                    HStack {
                        Image(systemName: "applelogo")
                        Text("Continue with Apple")
                    }
                    .font(Theme.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Color.black)
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .padding(.horizontal, Theme.Spacing.lg)

                // Sign Up Link
                HStack {
                    Text("Don't have an account?")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Button("Sign Up") {
                        onSignUpTap()
                    }
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.primary)
                }
                .padding(.top, Theme.Spacing.md)

                Spacer()
            }
        }
        .background(Theme.Colors.background)
        .onAppear {
            AnalyticsTracker.shared.track(.signInView)
        }
    }

    private func handleSignIn() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    SignInView(onSignUpTap: {}, onAppleSignInTap: {})
        .environmentObject(AuthService.shared)
}
