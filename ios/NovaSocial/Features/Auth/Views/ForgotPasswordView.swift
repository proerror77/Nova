import SwiftUI

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    // MARK: - Design Constants
    private enum Layout {
        static let contentOffset: CGFloat = 120
        static let inputFieldHeight: CGFloat = 49
        static let buttonHeight: CGFloat = 46
        static let buttonCornerRadius: CGFloat = 31.5
        static let fieldCornerRadius: CGFloat = 6
        static let errorOffset: CGFloat = 32
    }

    private enum Colors {
        static let placeholder = Color(white: 0.77)
        static let errorText = Color(red: 1, green: 0.4, blue: 0.4)
        static let fieldBorder = Color.white.opacity(0.3)
    }

    // MARK: - Binding
    @Binding var currentPage: AppPage

    // MARK: - Environment
    @EnvironmentObject private var authManager: AuthenticationManager

    // MARK: - State
    @State private var email = ""
    @State private var isLoading = false
    @State private var showSuccessAlert = false
    @State private var emailError: String?

    // MARK: - Focus State
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        ZStack {
            // Background Image
            Image("Registration-background")
                .resizable()
                .scaledToFill()
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
                        VStack(spacing: 0) {
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
                                .foregroundColor(Colors.placeholder)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Spacer()
                                .frame(height: 36)

                            // Email Input
                            emailTextField
                                .padding(.horizontal, 16)

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
                        .offset(y: Layout.contentOffset)

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
        .navigationBarHidden(true)
        .onChange(of: showSuccessAlert) { _, newValue in
            if newValue {
                // Navigate to email sent confirmation view
                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                currentPage = .emailSentConfirmation(email: trimmedEmail)
            }
        }
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
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Layout.fieldCornerRadius)
                .fill(Color.clear)
                .frame(height: Layout.inputFieldHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.fieldCornerRadius)
                        .stroke(emailError != nil ? Color.red : Colors.fieldBorder, lineWidth: emailError != nil ? 1 : 0.5)
                )

            TextField("", text: $email, prompt: Text(LocalizedStringKey("Enter_Your_Email")).foregroundColor(Colors.placeholder))
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

            if let error = emailError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Colors.errorText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
                    .offset(y: Layout.errorOffset)
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
            .frame(height: Layout.buttonHeight)
            .background(Color.white)
            .cornerRadius(Layout.buttonCornerRadius)
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1.0)
        .accessibilityIdentifier("sendResetLinkButton")
    }

    // MARK: - Back to Login Button
    private var backToLoginButton: some View {
        Button(action: {
            currentPage = .login
        }) {
            Text(LocalizedStringKey("Back_To_Login"))
                .font(.system(size: 12, weight: .medium))
                .underline()
                .foregroundColor(.white)
        }
    }

    // MARK: - Actions

    private func handleSubmit() async {
        guard validateEmail() else { return }

        isLoading = true
        emailError = nil

        do {
            try await authManager.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            showSuccessAlert = true
        } catch {
            // Always show success message to prevent email enumeration
            // The backend also always returns success
            showSuccessAlert = true

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
            emailError = "Please_enter_your_email"
            return false
        }

        if !isValidEmail(trimmedEmail) {
            emailError = "Invalid_email_format"
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

// MARK: - Previews

#Preview("ForgotPassword - Default") {
    ForgotPasswordView(currentPage: .constant(.forgotPassword))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("ForgotPassword - Dark Mode") {
    ForgotPasswordView(currentPage: .constant(.forgotPassword))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
