import SwiftUI

struct CreateAccountView: View {
    @Binding var currentPage: AppPage
    @State private var email = ""
    @State private var isLoading = false
    @State private var isGoogleLoading = false
    @State private var isAppleLoading = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    // Access global AuthenticationManager
    @EnvironmentObject private var authManager: AuthenticationManager

    private var isEmailValid: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    var body: some View {
        ZStack {
            // Background - Linear Gradient (same as CAPhoneNumberView)
            LinearGradient(
                colors: [
                    Color(red: 0.027, green: 0.106, blue: 0.212),  // #071B36
                    Color(red: 0.271, green: 0.310, blue: 0.388)   // #454F63
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                Spacer().frame(height: 114.h)
                logoSection
                Spacer().frame(height: 43.h)
                titleSection
                Spacer().frame(height: 55.h)
                phoneButton.padding(.horizontal, 37.w)
                Spacer().frame(height: 15.h)
                orText
                Spacer().frame(height: 15.h)
                googleButton.padding(.horizontal, 37.w)
                Spacer().frame(height: 24.h)
                appleButton.padding(.horizontal, 37.w)
                Spacer().frame(height: 293.h)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Back Button - Top Left
            VStack {
                HStack {
                    Button(action: { currentPage = .inviteCode }) {
                        Image("back-white")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24.s, height: 24.s)
                    }
                    Spacer()
                }
                .padding(.leading, 20.w)
                .padding(.top, 64.h)
                
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Components

    private var logoSection: some View {
        ZStack {
            Image("Login-Icon")
                .resizable()
                .scaledToFit()
        }
        .frame(width: 84.w, height: 52.h)
    }

    private var titleSection: some View {
        Text("Create New Account")
            .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
            .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))
    }

    private var phoneButton: some View {
        Button(action: {
            currentPage = .createAccountPhoneNumber
        }) {
            HStack(spacing: 0) {
                Spacer().frame(width: 18.w)
                Image("Phone-2")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18.s, height: 18.s)
                Spacer().frame(width: 45.w)
                Text("Use Mobile Number")
                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 18.w)
            }
            .frame(height: 47.h)
            .frame(maxWidth: .infinity)
            .background(.white)
            .cornerRadius(65.s)
        }
    }

    private var orText: some View {
        Text("or")
            .font(Font.custom("SFProDisplay-Regular", size: 16.f))
            .foregroundColor(.white)
    }

    private var googleButton: some View {
        Button(action: {
            Task { await handleGoogleSignIn() }
        }) {
            HStack(spacing: 0) {
                Spacer().frame(width: 18.w)
                if isGoogleLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                        .frame(width: 18.s, height: 18.s)
                } else {
                    Image("Google（B）")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18.s, height: 18.s)
                }
                Spacer().frame(width: 45.w)
                Text("Continue with Google")
                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 18.w)
            }
            .frame(height: 47.h)
            .frame(maxWidth: .infinity)
            .background(.white)
            .cornerRadius(65.s)
        }
        .disabled(isGoogleLoading || isAppleLoading)
    }

    private var appleButton: some View {
        Button(action: {
            Task { await handleAppleSignIn() }
        }) {
            HStack(spacing: 0) {
                Spacer().frame(width: 18.w)
                if isAppleLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                        .frame(width: 18.s, height: 18.s)
                } else {
                    Image("Apple（B）")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18.s, height: 18.s)
                }
                Spacer().frame(width: 45.w)
                Text("Continue with Apple")
                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 18.w)
            }
            .frame(height: 47.h)
            .frame(maxWidth: .infinity)
            .background(.white)
            .cornerRadius(65.s)
        }
        .disabled(isGoogleLoading || isAppleLoading)
    }

    private var emailInput: some View {
        TextField("", text: $email, prompt: Text("Email address")
            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6)))
            .font(Font.custom("SFProDisplay-Light", size: 16.f))
            .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .focused($isInputFocused)
            .padding(EdgeInsets(top: 13.h, leading: 20.w, bottom: 13.h, trailing: 20.w))
            .frame(width: 300.w, height: 48.h)
            .background(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
            .cornerRadius(43.s)
            .overlay(
                RoundedRectangle(cornerRadius: 43.s)
                    .inset(by: 0.50)
                    .stroke(.white, lineWidth: 0.50)
            )
    }

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage {
            Text(LocalizedStringKey(errorMessage))
                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40.w)
                .padding(.top, 12.h)
        }
    }

    private var continueButton: some View {
        Button(action: { Task { await submitEmail() } }) {
            HStack(spacing: 8.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text("Continue")
                    .font(Font.custom("SFProDisplay-Heavy", size: 16.f))
                    .tracking(0.32)
                    .foregroundColor(.black)
            }
            .frame(width: 300.w, height: 48.h)
            .background(Color.white.opacity(isEmailValid ? 1 : 0.5))
            .cornerRadius(43.s)
        }
        .disabled(!isEmailValid || isLoading)
    }

    // MARK: - Actions

    private func submitEmail() async {
        guard isEmailValid else { return }

        isLoading = true
        errorMessage = nil

        // TODO: Implement email submission logic
        // This will need backend API integration

        try? await Task.sleep(for: .milliseconds(500))

        isLoading = false
    }

    // MARK: - OAuth Sign-In

    private func handleGoogleSignIn() async {
        isGoogleLoading = true
        errorMessage = nil

        do {
            // Use the validated invite code from the registration flow
            let _ = try await authManager.loginWithGoogle(inviteCode: authManager.validatedInviteCode)
            // Success - AuthenticationManager will update isAuthenticated
            // Clear the invite code after successful registration
            await MainActor.run {
                authManager.validatedInviteCode = nil
            }
        } catch let error as OAuthError {
            if case .userCancelled = error {
                // User cancelled, no error message needed
            } else if case .invalidInviteCode(let message) = error {
                errorMessage = message
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            let errorDesc = error.localizedDescription.lowercased()
            if !errorDesc.contains("cancel") {
                errorMessage = "Google sign in failed. Please try again."
                #if DEBUG
                print("[CreateAccountView] Google sign in error: \(error)")
                #endif
            }
        }

        isGoogleLoading = false
    }

    private func handleAppleSignIn() async {
        isAppleLoading = true
        errorMessage = nil

        do {
            // Use the validated invite code from the registration flow
            let _ = try await authManager.loginWithApple(inviteCode: authManager.validatedInviteCode)
            // Success - AuthenticationManager will update isAuthenticated
            // Clear the invite code after successful registration
            await MainActor.run {
                authManager.validatedInviteCode = nil
            }
        } catch let error as OAuthError {
            if case .userCancelled = error {
                // User cancelled, no error message needed
            } else if case .invalidInviteCode(let message) = error {
                errorMessage = message
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            let errorDesc = error.localizedDescription.lowercased()
            if !errorDesc.contains("cancel") {
                errorMessage = "Apple sign in failed. Please try again."
                #if DEBUG
                print("[CreateAccountView] Apple sign in error: \(error)")
                #endif
            }
        }

        isAppleLoading = false
    }
}

#Preview {
    CreateAccountView(currentPage: .constant(.createAccount))
        .environmentObject(AuthenticationManager.shared)
}
