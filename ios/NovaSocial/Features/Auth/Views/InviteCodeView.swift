import SwiftUI

struct InviteCodeView: View {
    @Binding var currentPage: AppPage
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    /// 整体内容垂直偏移（负值上移，正值下移）
    private let contentVerticalOffset: CGFloat = -50

    private var isInviteCodeValid: Bool { inviteCode.count == 8 }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Image("Registration-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                Color.black.opacity(0.4).ignoresSafeArea()

                // Content
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
                    goBackButton
                }
                .offset(y: contentVerticalOffset)
            }
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = false }
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Components

    private var logoSection: some View {
        Image("Logo-R")
            .resizable()
            .scaledToFit()
            .frame(height: 90)
            .colorInvert()
            .brightness(1)
    }

    private var titleSection: some View {
        VStack(spacing: 16) {
            Text("Enter invite code")
                .font(Typography.semibold24)
                .foregroundColor(.white)

            Text("lf you have an invite code\nEnter it below.")
                .font(Typography.light14)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(white: 0.77))
        }
    }

    private var inviteCodeInput: some View {
        ZStack {
            TextField("", text: $inviteCode)
                .font(Typography.regular16)
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
                    .font(Typography.regular16)
                    .tracking(4)
                    .foregroundColor(Color(white: 0.97))
                if inviteCode.count < 8 {
                    Text("—")
                        .font(Typography.regular16)
                        .foregroundColor(Color(white: 0.97))
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(Color(white: 0.27).opacity(0.45))
        .cornerRadius(43)
        .overlay(RoundedRectangle(cornerRadius: 43).stroke(Color(white: 0.53), lineWidth: 0.5))
        .onTapGesture { isInputFocused = true }
    }

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage {
            Text(LocalizedStringKey(errorMessage))
                .font(Typography.regular12)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 12)
        }
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
                    .font(Typography.semibold16)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.white.opacity(isInviteCodeValid ? 1 : 0.5))
            .cornerRadius(43)
        }
        .disabled(!isInviteCodeValid || isLoading)
    }

    private var goBackButton: some View {
        Button(action: { currentPage = .login }) {
            Text("Go back")
                .font(Typography.bold12)
                .underline()
                .foregroundColor(.white)
        }
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
            print("[InviteCodeView] Invite code validation error: \(error)")
            print("[InviteCodeView] Error details: \(error.localizedDescription)")
            print("[InviteCodeView] Error type: \(type(of: error))")
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

#Preview {
    InviteCodeView(currentPage: .constant(.inviteCode))
}
