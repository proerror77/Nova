import SwiftUI

/// Phone Number Enter Code View - (PN) EnterCode
/// Verification code entry screen for phone number registration flow
struct PhoneEnterCodeView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    
    /// The full phone number (with country code) for verification
    let phoneNumber: String
    
    // MARK: - State
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var countdown: Int = 60
    @State private var canResend = false
    @State private var verificationToken = ""
    @FocusState private var isInputFocused: Bool
    
    /// Timer for countdown
    @State private var timer: Timer?
    
    private var isCodeValid: Bool { verificationCode.count == 6 }
    
    /// Masked phone number for display (e.g., "***8664")
    private var maskedPhoneNumber: String {
        guard phoneNumber.count >= 4 else { return phoneNumber }
        let lastFour = String(phoneNumber.suffix(4))
        return "***\(lastFour)"
    }
    
    var body: some View {
        ZStack {
            // Background - Solid color per Figma
            Color(red: 0.03, green: 0.11, blue: 0.21)
            
            // Content
            VStack(spacing: 0) {
                Spacer().frame(height: 120.h)  // 统一顶部间距 (44 status + 64 header + 12 buffer)
                logoSection
                Spacer().frame(height: 30.h)
                titleSection
                Spacer().frame(height: 40.h)
                codeInputSection
                    .padding(.horizontal, 37.w)
                errorMessageView
                Spacer().frame(height: 24.h)
                verifyButton
                    .padding(.horizontal, 37.w)
                Spacer().frame(height: 40.h)
                resendSection
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Back Button Header - Figma: 375x64, padding 8
            VStack(spacing: 0) {
                Spacer().frame(height: 44.h)  // Status bar safe area
                HStack(spacing: 8.s) {
                    Button(action: {
                        // Navigate back to phone number input
                        currentPage = .createAccountPhoneNumber
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 40.s, height: 40.s)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 24.f, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24.s, height: 24.s)
                        }
                        .frame(width: 48.s, height: 48.s)
                    }
                    Spacer()
                }
                .padding(8.s)
                .frame(height: 64.h)
                Spacer()
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
        .onAppear {
            startCountdown()
            isInputFocused = true
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Components
    
    private var logoSection: some View {
        VStack(spacing: 8.h) {
            Image("Login-Icon")
                .resizable()
                .scaledToFit()
                .frame(width: 84.w, height: 52.h)
            
            Text("ICERED")
                .font(Font.custom("SFProDisplay-Bold", size: 16.f))
                .tracking(4)
                .foregroundColor(.white)
        }
    }
    
    private var titleSection: some View {
        VStack(spacing: 12.h) {
            Text("Enter your confirmation code")
                .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                .foregroundColor(.white)
            
            Text("An SMS was sent to \(maskedPhoneNumber).")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .tracking(0.28)
                .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.75))
        }
    }
    
    private var codeInputSection: some View {
        OTPInputView(code: $verificationCode, codeLength: 6)
            .onChange(of: verificationCode) { _, newValue in
                // Auto-verify when 6 digits entered
                if newValue.count == 6 {
                    Task { await verifyCode() }
                }
            }
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
    
    private var verifyButton: some View {
        Button(action: { Task { await verifyCode() } }) {
            HStack(spacing: 10.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text("Verify")
                    .font(Font.custom("SFProDisplay-Bold", size: 16.f))
                    .foregroundColor(.black)
            }
            .frame(width: 301.w, height: 48.h)
            .background(Color.white)
            .cornerRadius(50.s)
        }
        .disabled(!isCodeValid || isLoading)
    }
    
    private var resendSection: some View {
        VStack(spacing: 8.h) {
            // Resend code button
            Button(action: {
                Task { await resendCode() }
            }) {
                Text("Resend code")
                    .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                    .tracking(0.28)
                    .underline()
                    .foregroundColor(.white)
            }
            .disabled(!canResend || isLoading)
            
            // Countdown timer text
            if !canResend {
                Text("You can request a new code in \(countdown) seconds.")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.75))
            }
        }
    }
    
    // MARK: - Timer
    
    private func startCountdown() {
        countdown = 60
        canResend = false
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                canResend = true
                timer?.invalidate()
            }
        }
    }
    
    // MARK: - API Actions
    
    private func verifyCode() async {
        guard isCodeValid else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await PhoneAuthService.shared.verifyCode(
                phoneNumber: phoneNumber,
                code: verificationCode
            )
            
            if response.success, let token = response.verificationToken {
                verificationToken = token
                // Store verification token with timestamp for next step
                authManager.setPhoneVerificationToken(token, phoneNumber: phoneNumber)

                // Navigate to profile setup
                await MainActor.run {
                    currentPage = .profileSetup
                }
            } else {
                errorMessage = response.message ?? "Verification failed"
                verificationCode = ""
            }
        } catch let phoneError as PhoneAuthError {
            #if DEBUG
            print("[PNEnterCodeView] Verification error: \(phoneError)")
            #endif
            switch phoneError {
            case .invalidCode:
                errorMessage = "Invalid code. Please check and try again."
            case .codeExpired:
                errorMessage = "Code has expired. Please request a new code."
            case .rateLimited:
                errorMessage = "Too many attempts. Please wait before trying again."
            case .networkError:
                errorMessage = "Unable to connect. Please check your internet connection."
            case .serverError(let message):
                errorMessage = message
            default:
                errorMessage = phoneError.localizedDescription
            }
            verificationCode = ""
        } catch {
            #if DEBUG
            print("[PNEnterCodeView] Unexpected error: \(error)")
            #endif
            errorMessage = "An unexpected error occurred. Please try again."
            verificationCode = ""
        }
        
        isLoading = false
    }
    
    private func resendCode() async {
        guard canResend else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await PhoneAuthService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            
            if response.success {
                // Restart countdown
                await MainActor.run {
                    startCountdown()
                }
            } else {
                errorMessage = response.message ?? "Failed to resend code"
            }
        } catch let phoneError as PhoneAuthError {
            #if DEBUG
            print("[PNEnterCodeView] Resend error: \(phoneError)")
            #endif
            switch phoneError {
            case .rateLimited:
                errorMessage = "Too many attempts. Please wait before trying again."
            case .networkError:
                errorMessage = "Unable to connect. Please check your internet connection."
            default:
                errorMessage = phoneError.localizedDescription
            }
        } catch {
            #if DEBUG
            print("[PNEnterCodeView] Unexpected resend error: \(error)")
            #endif
            errorMessage = "Failed to resend code. Please try again."
        }
        
        isLoading = false
    }
}

#Preview {
    PhoneEnterCodeView(
        currentPage: .constant(.phoneEnterCode(phoneNumber: "+14155558664")),
        phoneNumber: "+14155558664"
    )
    .environmentObject(AuthenticationManager.shared)
}
