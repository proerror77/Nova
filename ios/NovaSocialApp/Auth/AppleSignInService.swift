import Foundation
import AuthenticationServices

/// Sign in with Apple flow using AuthenticationServices
final class AppleSignInService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    typealias Completion = (Result<(code: String, state: String), Error>) -> Void

    private var completion: Completion?

    func signIn(completion: @escaping Completion) {
        self.completion = completion

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        // Generate state and nonce
        let manager = OAuthStateManager.shared
        let state = manager.generateState()
        let rawNonce = manager.generateNonce()
        let hashed = manager.sha256(rawNonce)

        request.state = state
        if #available(iOS 13.0, *) {
            request.nonce = hashed
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - ASAuthorizationControllerDelegate
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            self.completion?(.failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing credential"])) )
            return
        }

        // Extract authorizationCode from credential
        if let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) {
            let state = credential.state ?? (OAuthStateManager.shared.currentState() ?? "")
            completion?(.success((code: code, state: state)))
        } else {
            completion?(.failure(NSError(domain: "AppleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "No authorization code"])) )
        }

        // Clear state/nonce after use
        OAuthStateManager.shared.clearState()
        OAuthStateManager.shared.clearNonce()
        self.completion = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        self.completion = nil
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Best effort: return key window
        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? UIWindow()
    }
}

