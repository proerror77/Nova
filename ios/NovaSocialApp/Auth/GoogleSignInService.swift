import Foundation
import AuthenticationServices

/// Google Sign-In via ASWebAuthenticationSession (fallback when GoogleSignIn SDK is unavailable)
final class GoogleSignInService: NSObject {
    private var session: ASWebAuthenticationSession?

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        // Build Google OAuth URL
        let state = OAuthStateManager.shared.generateState()
        let nonce = OAuthStateManager.shared.generateNonce()

        // Configure these values according to your Google OAuth client
        let clientID = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] ?? "YOUR_GOOGLE_CLIENT_ID"
        let redirectURI = "novasocial://auth/oauth/google"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce)
        ]

        guard let url = comps.url else {
            completion(.failure(NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])) )
            return
        }

        // Open OAuth consent in ASWebAuthenticationSession
        session = ASWebAuthenticationSession(url: url, callbackURLScheme: "novasocial") { _, error in
            if let error = error { completion(.failure(error)); return }
            completion(.success(()))
        }
        session?.presentationContextProvider = self
        session?.start()
    }
}

extension GoogleSignInService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.windows.first { $0.isKeyWindow } ?? UIWindow()
    }
}

