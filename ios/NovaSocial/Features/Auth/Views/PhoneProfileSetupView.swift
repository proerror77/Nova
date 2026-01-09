import SwiftUI

// MARK: - Phone Profile Setup View

/// Profile setup view for phone registration after invite code validation
/// This is the final step in the phone registration flow
struct PhoneProfileSetupView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Get stored phone verification data
    private var phoneNumber: String {
        authManager.verifiedPhoneNumber ?? ""
    }

    private var verificationToken: String {
        authManager.phoneVerificationToken ?? ""
    }

    private var isProfileValid: Bool {
        username.count >= 3 &&
        password.count >= 6 &&
        password == confirmPassword
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        // Description
                        Text("Create your account")
                            .font(Font.custom("SFProDisplay-Bold", size: 20.f))
                            .foregroundColor(.white)
                            .padding(.bottom, 10)

                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.gray)

                            TextField("", text: $username, prompt: Text("Choose a username").foregroundColor(.gray))
                                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                                .foregroundColor(.white)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }

                        // Display name field (optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name (optional)")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.gray)

                            TextField("", text: $displayName, prompt: Text("How should we call you?").foregroundColor(.gray))
                                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.gray)

                            SecureField("", text: $password, prompt: Text("Create a password").foregroundColor(.gray))
                                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }

                        // Confirm password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.gray)

                            SecureField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(.gray))
                                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }

                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Register button
                        Button(action: {
                            Task { await completeRegistration() }
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                                Text("Create Account")
                                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isProfileValid ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray)
                            .cornerRadius(25)
                        }
                        .disabled(!isProfileValid || isLoading)
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: {
                // Go back to invite code page
                currentPage = .inviteCode
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20.f))
                    .foregroundColor(.white)
            }

            Spacer()

            Text("Complete Profile")
                .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                .foregroundColor(.white)

            Spacer()

            // Placeholder for alignment
            Image(systemName: "chevron.left")
                .font(.system(size: 20.f))
                .foregroundColor(.clear)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func completeRegistration() async {
        guard validateProfile() else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await PhoneAuthService.shared.registerWithPhone(
                phoneNumber: phoneNumber,
                verificationToken: verificationToken,
                username: username,
                password: password,
                displayName: displayName.isEmpty ? nil : displayName,
                inviteCode: authManager.validatedInviteCode
            )

            // Save auth tokens
            if let user = response.user {
                authManager.updateCurrentUser(user)
            }

            // Set flag to show welcome screen for first-time registration
            UserDefaults.standard.set(true, forKey: "shouldShowWelcome")

            // Navigate to welcome (will then go to home after showing)
            await MainActor.run {
                currentPage = .welcome
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func validateProfile() -> Bool {
        if username.count < 3 {
            errorMessage = "Username must be at least 3 characters"
            return false
        }

        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters"
            return false
        }

        if password != confirmPassword {
            errorMessage = "Passwords do not match"
            return false
        }

        return true
    }
}

// MARK: - Preview

#Preview {
    PhoneProfileSetupView(currentPage: .constant(.phoneProfileSetup))
        .environmentObject(AuthenticationManager.shared)
}
