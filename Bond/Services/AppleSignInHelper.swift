import AuthenticationServices
import CryptoKit
import Foundation

/// Nonce management for Sign in with Apple. The button itself is the native
/// `SignInWithAppleButton` (driven from its own `onRequest`/`onCompletion`) -
/// no transparent overlay. This type only owns the nonce lifecycle and
/// credential extraction.
@MainActor
final class AppleSignInHelper {
    private var currentNonce: String?

    /// Generates a fresh nonce, stores it for verification, and returns the
    /// SHA256 hash to attach to the authorization request.
    func beginRequest() -> String {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        return Self.sha256(nonce)
    }

    /// Extracts the id token + original nonce from a completed authorization.
    func credential(
        from authorization: ASAuthorization
    ) throws -> (idToken: String, nonce: String) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            throw AppleSignInError.invalidCredential
        }
        currentNonce = nil
        return (idToken, nonce)
    }

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess)
            for r in randoms where remaining > 0 {
                if r < charset.count {
                    result.append(charset[Int(r)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum AppleSignInError: Error { case invalidCredential }
