import SwiftUI

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager

    // MARK: - State
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var emailError: String?

    // MARK: - Focus State
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        ZStack {
            // Background Image
            Image("Registration-background")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea(.all)

            // Dark overlay
            Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            // Main Content
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        let contentVerticalOffset: CGFloat = 120

                        VStack(spacing: 0) {
                            // Back button
                            HStack {
                                Button(action: {
                                    dismiss()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .medium))
                                        Text(LocalizedStringKey("Back"))
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)

                            Spacer()
                                .frame(height: 40)

                            // Logo Section
                            logoSection

                            Spacer()
                                .frame(height: 40)

                            // Title
                            Text(LocalizedStringKey("Forgot_Password_Title"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Spacer()
                                .frame(height: 16)

                            // Description
                            Text(LocalizedStringKey("Forgot_Password_Description"))
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Spacer()
                                .frame(height: 36)

                            // Email Input
                            emailTextField
                                .padding(.horizontal, 16)

                            // Error Message
                            if let errorMessage = errorMessage {
                                Text(LocalizedStringKey(errorMessage))
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 12)
                            }

                            // Success Message
                            if let successMessage = successMessage {
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.green)

                                    Text(LocalizedStringKey(successMessage))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.green)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                .padding(.top, 24)
                            }

                            Spacer()
                                .frame(height: 32)

                            // Submit Button
                            submitButton
                                .padding(.horizontal, 16)

                            Spacer()
                                .frame(height: 16)

                            // Back to Login Button
                            backToLoginButton
                        }
                        .offset(y: contentVerticalOffset)

                        Spacer()
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarHidden(true)
    }

    // MARK: - Logo Section
    private var logoSection: some View {
        VStack(spacing: 4) {
            Image("Logo-R")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .colorInvert()
                .brightness(1)
        }
    }

    // MARK: - Email TextField
    private var emailTextField: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(height: 49)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(emailError != nil ? Color.red : Color.white.opacity(0.3), lineWidth: emailError != nil ? 1 : 0.5)
                    )

                TextField("", text: $email, prompt: Text(LocalizedStringKey("Enter_Your_Email")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .light))
                    .padding(.horizontal, 16)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("forgotPasswordEmailTextField")
                    .focused($isEmailFocused)
                    .onChange(of: email) { _, newValue in
                        validateEmailRealtime(newValue)
                    }
            }

            if let error = emailError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        Button(action: {
            Task {
                await handleSubmit()
            }
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text(LocalizedStringKey("Send_Reset_Link"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.white)
            .cornerRadius(31.50)
        }
        .disabled(isLoading || successMessage != nil)
        .opacity(successMessage != nil ? 0.5 : 1.0)
        .accessibilityIdentifier("sendResetLinkButton")
    }

    // MARK: - Back to Login Button
    private var backToLoginButton: some View {
        Button(action: {
            dismiss()
        }) {
            Text(LocalizedStringKey("Back_To_Login"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
        }
    }

    // MARK: - Actions

    private func handleSubmit() async {
        guard validateEmail() else { return }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            try await authManager.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            successMessage = "Password_Reset_Email_Sent"
        } catch {
            // Always show success message to prevent email enumeration
            // The backend also always returns success
            successMessage = "Password_Reset_Email_Sent"

            #if DEBUG
            print("[ForgotPasswordView] Request error (hidden from user): \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Validation

    private func validateEmail() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty {
            errorMessage = "Please_enter_your_email"
            return false
        }

        if !isValidEmail(trimmedEmail) {
            errorMessage = "Please_enter_a_valid_email"
            return false
        }

        return true
    }

    private func validateEmailRealtime(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emailError = nil
        } else if !isValidEmail(trimmed) {
            emailError = "Invalid_email_format"
        } else {
            emailError = nil
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
}

// MARK: - Preview

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthenticationManager.shared)
}
