import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PurchasesService.self) private var purchases
    @Environment(\.colorScheme) private var colorScheme
    @State private var appleHelper = AppleSignInHelper()
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            BondHero(subtitle: "Small acts of love, on cue.")
            Spacer()
            Spacer()

            VStack(spacing: BondSpacing.m) {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.large)
                        .frame(height: 50)
                        .padding(.horizontal, BondSpacing.base)
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = appleHelper.beginRequest()
                    } onCompletion: { result in
                        Task { await handle(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .whiteOutline : .black)
                    .frame(height: 50)
                    .padding(.horizontal, BondSpacing.base)
                }

                if let errorMessage {
                    BondInlineError(message: errorMessage)
                }

                legalFooter
            }
            .padding(.bottom, BondSpacing.xxxl)
        }
        .padding(.top, BondSpacing.xxxl)
    }

    private var legalFooter: some View {
        Text("By continuing you accept the [Terms](https://jackwallner.github.io/bond/terms) and [Privacy Policy](https://jackwallner.github.io/bond/privacy).")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .tint(.bondAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, BondSpacing.xl)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                let cred = try appleHelper.credential(from: authorization)
                try await supabase.signInWithApple(idToken: cred.idToken, nonce: cred.nonce)
                if let me = supabase.currentUserId {
                    await purchases.identify(supabaseUserId: me)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            // User-cancelled is silent — not worth surfacing.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
