import SwiftUI

// MARK: - Email Sent Confirmation View

/// View shown after user requests password reset
/// Instructs user to check their email for the reset link
struct EmailSentConfirmationView: View {
    // MARK: - Design Constants
    private enum Layout {
        static let contentOffset: CGFloat = 120
        static let buttonHeight: CGFloat = 46
        static let buttonCornerRadius: CGFloat = 31.5
        static let iconSize: CGFloat = 80
    }

    private enum Colors {
        static let placeholder = Color(white: 0.77)
        static let successGreen = Color(red: 0.4, green: 0.8, blue: 0.4)
    }

    // MARK: - Binding
    @Binding var currentPage: AppPage

    // MARK: - Properties
    let email: String

    // MARK: - State
    @State private var isResending = false
    @State private var showResendSuccess = false
    @State private var resendCooldown = 0
    @State private var cooldownTimer: Timer?

    // MARK: - Environment
    @EnvironmentObject private var authManager: AuthenticationManager

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
                                .frame(height: 60)

                            // Logo Section
                            logoSection

                            Spacer()
                                .frame(height: 40)

                            // Success Icon
                            Image(systemName: "envelope.circle.fill")
                                .font(.system(size: Layout.iconSize))
                                .foregroundColor(Colors.successGreen)

                            Spacer()
                                .frame(height: 24)

                            // Title
                            Text(LocalizedStringKey("Email_Sent_Title"))
                                .font(Font.custom("SFProDisplay-Bold", size: 28.f))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Spacer()
                                .frame(height: 16)

                            // Description
                            Text(LocalizedStringKey("Email_Sent_Description"))
                                .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                .foregroundColor(Colors.placeholder)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Spacer()
                                .frame(height: 8)

                            // Email display
                            Text(email)
                                .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Spacer()
                                .frame(height: 32)

                            // Instructions
                            instructionsSection

                            Spacer()
                                .frame(height: 40)

                            // Open Email App Button
                            openEmailButton
                                .padding(.horizontal, 16)

                            Spacer()
                                .frame(height: 16)

                            // Resend Email Button
                            resendButton

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
            }
        }
        .navigationBarHidden(true)
        .alert(LocalizedStringKey("Email_Resent_Title"), isPresented: $showResendSuccess) {
            Button("OK") {}
        } message: {
            Text(LocalizedStringKey("Email_Resent_Message"))
        }
        .onDisappear {
            cooldownTimer?.invalidate()
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

    // MARK: - Instructions Section
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            instructionRow(number: "1", text: "Check_Email_Instruction_1")
            instructionRow(number: "2", text: "Check_Email_Instruction_2")
            instructionRow(number: "3", text: "Check_Email_Instruction_3")
        }
        .padding(.horizontal, 32)
    }

    private func instructionRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(Font.custom("SFProDisplay-Bold", size: 14.f))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.2)))

            Text(text)
                .font(Font.custom("SFProDisplay-Light", size: 14.f))
                .foregroundColor(Colors.placeholder)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Open Email Button
    private var openEmailButton: some View {
        Button(action: openEmailApp) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 18.f))
                Text(LocalizedStringKey("Open_Email_App"))
                    .font(Font.custom("SFProDisplay-Bold", size: 20.f))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.buttonHeight)
            .background(Color.white)
            .cornerRadius(Layout.buttonCornerRadius)
        }
    }

    // MARK: - Resend Button
    private var resendButton: some View {
        Button(action: {
            Task {
                await resendEmail()
            }
        }) {
            HStack(spacing: 8) {
                if isResending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                if resendCooldown > 0 {
                    Text("Resend in \(resendCooldown)s")
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(Colors.placeholder)
                } else {
                    Text(LocalizedStringKey("Resend_Email"))
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(isResending || resendCooldown > 0)
        .opacity(resendCooldown > 0 ? 0.5 : 1.0)
    }

    // MARK: - Back to Login Button
    private var backToLoginButton: some View {
        Button(action: {
            currentPage = .login
        }) {
            Text(LocalizedStringKey("Back_To_Login"))
                .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                .underline()
                .foregroundColor(.white)
        }
    }

    // MARK: - Actions

    private func openEmailApp() {
        if let mailURL = URL(string: "message://") {
            if UIApplication.shared.canOpenURL(mailURL) {
                UIApplication.shared.open(mailURL)
            } else if let gmailURL = URL(string: "googlegmail://") {
                if UIApplication.shared.canOpenURL(gmailURL) {
                    UIApplication.shared.open(gmailURL)
                }
            }
        }
    }

    private func resendEmail() async {
        isResending = true

        do {
            try await authManager.requestPasswordReset(email: email)
            showResendSuccess = true
            startCooldown()
        } catch {
            // Still show success to prevent email enumeration
            showResendSuccess = true
            startCooldown()

            #if DEBUG
            print("[EmailSentConfirmationView] Resend error (hidden): \(error)")
            #endif
        }

        isResending = false
    }

    private func startCooldown() {
        resendCooldown = 60 // 60 seconds cooldown
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if resendCooldown > 0 {
                resendCooldown -= 1
            } else {
                cooldownTimer?.invalidate()
            }
        }
    }
}

// MARK: - Previews

#Preview("EmailSentConfirmation - Default") {
    EmailSentConfirmationView(currentPage: .constant(.emailSentConfirmation(email: "test@example.com")), email: "test@example.com")
        .environmentObject(AuthenticationManager.shared)
}
