import SwiftUI

struct WelcomeView: View {
    // MARK: - Design Constants
    private enum Layout {
        static let contentOffset: CGFloat = 200
        static let buttonHeight: CGFloat = 46
        static let buttonCornerRadius: CGFloat = 43
    }

    private enum Colors {
        static let placeholder = Color(white: 0.77)
        static let secondaryText = Color(white: 0.53)
        static let inputBackground = Color(white: 0.27).opacity(0.45)
        static let inputBorder = Color(white: 0.53)
    }

    // MARK: - Binding
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // MARK: - Focus State
    @FocusState private var isInputFocused: Bool

    // MARK: - Computed Properties
    private var isInviteCodeValid: Bool { inviteCode.count == 8 }

    var body: some View {
        ZStack {
            // Background
            Image("Registration-background")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea()

            Color.black.opacity(0.4).ignoresSafeArea()

            // Content - 与 LoginView 保持一致的布局结构
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    logoSection
                    Spacer().frame(height: 40)
                    titleSection
                    Spacer().frame(height: 28)
                    inviteCodeInput.padding(.horizontal, 16)
                    errorMessageView
                    Spacer().frame(height: 24)
                    doneButton.padding(.horizontal, 16)
                    Spacer().frame(height: 20)
                    notifyMeButton
                    Spacer().frame(height: 12)
                    goBackButton
                }
                .offset(y: Layout.contentOffset)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Components

    private var logoSection: some View {
        Image("Logo-R")
            .resizable()
            .scaledToFit()
            .frame(height: 50)
            .colorInvert()
            .brightness(1)
    }

    private var titleSection: some View {
        VStack(spacing: 16) {
            Text("Enter invite code")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text("lf you have an invite code\nEnter it below.")
                .font(.system(size: 14, weight: .light))
                .multilineTextAlignment(.center)
                .foregroundColor(Colors.placeholder)
        }
    }

    private var inviteCodeInput: some View {
        ZStack {
            TextField("", text: $inviteCode)
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.clear)
                .accentColor(.clear)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isInputFocused)
                .onChange(of: inviteCode) { _, newValue in
                    inviteCode = String(newValue.prefix(8)).uppercased()
                }

            HStack(spacing: 0) {
                Text(inviteCode)
                    .font(.system(size: 16, weight: .light))
                    .tracking(4)
                    .foregroundColor(Color(white: 0.97))
                if inviteCode.count < 8 {
                    Text("—")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(Color(white: 0.97))
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.buttonHeight)
        .background(Colors.inputBackground)
        .cornerRadius(Layout.buttonCornerRadius)
        .overlay(RoundedRectangle(cornerRadius: Layout.buttonCornerRadius).stroke(Colors.inputBorder, lineWidth: 0.5))
        .onTapGesture { isInputFocused = true }
    }

    @ViewBuilder
    private var errorMessageView: some View {
        // 使用固定高度容器，避免影响其他元素位置
        Text(errorMessage != nil ? LocalizedStringKey(errorMessage!) : " ")
            .font(.system(size: 12))
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .frame(minHeight: 20)
            .opacity(errorMessage != nil ? 1 : 0)
            .padding(.top, 12)
    }

    private var doneButton: some View {
        Button(action: { Task { await validateInviteCode() } }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text("Done")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, minHeight: Layout.buttonHeight)
            .background(Color.white.opacity(isInviteCodeValid ? 1 : 0.5))
            .cornerRadius(Layout.buttonCornerRadius)
        }
        .disabled(!isInviteCodeValid || isLoading)
    }

    private var goBackButton: some View {
        Button(action: { currentPage = .login }) {
            Text("Go back")
                .font(.system(size: 12, weight: .medium))
                .underline()
                .foregroundColor(.white)
        }
    }

    private var notifyMeButton: some View {
        HStack(spacing: 6) {
            Image("bell")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
            Text("Join the waitlist and get notified when access opens.")
                .font(Font.custom("Inter", size: 12))
                .foregroundColor(Colors.secondaryText)
        }
        .foregroundColor(Colors.secondaryText)
    }

    // MARK: - Validation

    private func validateInviteCode() async {
        guard isInviteCodeValid else { return }

        isLoading = true
        errorMessage = nil

        do {
            struct ValidateResponse: Codable {
                let isValid: Bool
                let issuerUsername: String?
                let expiresAt: Int64?
                let error: String?
            }

            let endpoint = "\(APIConfig.Invitations.validate)?code=\(inviteCode)"
            let response: ValidateResponse = try await APIClient.shared.request(endpoint: endpoint, method: "GET")

            if response.isValid {
                await MainActor.run { currentPage = .createAccount }
            } else {
                errorMessage = response.error ?? "Invalid_invite_code_generic"
            }
        } catch {
            // Handle network errors with detailed APIError handling
            #if DEBUG
            print("[WelcomeView] Invite code validation error: \(error)")
            print("[WelcomeView] Error details: \(error.localizedDescription)")
            print("[WelcomeView] Error type: \(type(of: error))")
            #endif

            if let apiError = error as? APIError {
                switch apiError {
                case .timeout, .noConnection, .networkError(_), .invalidResponse:
                    // Clear network-related errors
                    errorMessage = "Network_error"
                case .serverError(let statusCode, _):
                    if statusCode >= 500 {
                        // Backend / gateway unavailable (e.g. 503), treat as network issue
                        errorMessage = "Network_error"
                    } else {
                        // 4xx from server – treat as invalid code for now
                        errorMessage = "Invalid_invite_code_generic"
                    }
                case .notFound:
                    // Invite endpoint / code not found
                    errorMessage = "Invalid_invite_code_generic"
                default:
                    errorMessage = "Invalid_invite_code_generic"
                }
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Network_error"
            } else {
                errorMessage = "Invalid_invite_code_generic"
            }
        }

        isLoading = false
    }
}

// MARK: - Previews

#Preview("Welcome - Default") {
    WelcomeView(currentPage: .constant(.welcome))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Welcome - Dark Mode") {
    WelcomeView(currentPage: .constant(.welcome))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
