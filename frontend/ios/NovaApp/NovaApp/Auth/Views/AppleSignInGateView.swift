import SwiftUI
import AuthenticationServices

/// A03 - Apple Sign In Gate (template)
struct AppleSignInGateView: View {
    let onBack: () -> Void
    @EnvironmentObject var authService: AuthService

    var body: some View {
        VStack {
            Text("Apple Sign In")
                .font(Theme.Typography.h2)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                Task {
                    switch result {
                    case .success(let authorization):
                        try? await authService.signInWithApple(authorization: authorization)
                    case .failure(let error):
                        print("Apple Sign In failed: \(error)")
                    }
                }
            }
            .frame(height: 50)
            .padding()
        }
    }
}
