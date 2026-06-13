import AuthenticationServices
import SwiftUI

/// First-run onboarding for someone who opened Bond from their partner's
/// invite link. They didn't choose Bond - their partner did - so instead of
/// the solo intent setup ("Who do you want to show up for?") this screen
/// acknowledges the invite, explains what pairing gives them, and walks the
/// one required step (Apple Sign-In) before consuming the code. RootView
/// shows it whenever an invite code is pending and no couple exists yet.
struct InviteWelcomeView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PairingService.self) private var pairing
    @Environment(PurchasesService.self) private var purchases
    @Environment(\.colorScheme) private var colorScheme
    @State private var appleHelper = AppleSignInHelper()
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: BondSpacing.xl) {
            Spacer()

            VStack(spacing: BondSpacing.m) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.bondAccent.gradient)
                    .accessibilityHidden(true)
                Text("Your partner invited you")
                    .font(.bond(.title, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Bond is a small app for the two of you, little reminders, shared milestones, and a daily check-in.")
                    .font(.bond(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BondSpacing.xl)
            }

            if let code = pairing.deferredInviteCode {
                inviteCodeChip(code)
            }

            Spacer()

            VStack(spacing: BondSpacing.m) {
                if isWorking || pairing.isPairing {
                    ProgressView()
                        .controlSize(.large)
                        .frame(height: 52)
                } else if supabase.isAnonymous {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = appleHelper.beginRequest()
                    } onCompletion: { result in
                        Task { await handleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .whiteOutline : .black)
                    .frame(height: 52)
                    .padding(.horizontal, BondSpacing.base)

                    Text("Sign in with Apple so your partner stays paired with you across devices.")
                        .font(.bond(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BondSpacing.xl)
                } else {
                    // Already signed in (e.g. the first pairing attempt
                    // failed after sign-in) - offer the pair step directly.
                    BondPrimaryButton(title: "Accept invite") {
                        Task { await pairing.consumeDeferredInviteIfNeeded() }
                    }
                    .padding(.horizontal, BondSpacing.base)
                }

                if let message = errorMessage ?? pairing.lastError {
                    BondInlineError(message: message)
                }

                Button("Set up on my own instead") {
                    pairing.deferredInviteCode = nil
                    pairing.requiresSignInToPair = false
                    pairing.lastError = nil
                }
                .font(.bond(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, BondSpacing.xxxl)
        .onAppear { pairing.lastError = nil }
    }

    private func inviteCodeChip(_ code: String) -> some View {
        HStack(spacing: BondSpacing.s) {
            ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .frame(width: 36, height: 46)
                    .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Invite code: \(code.map(String.init).joined(separator: " "))")
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            isWorking = true
            defer { isWorking = false }
            do {
                let cred = try appleHelper.credential(from: authorization)
                try await supabase.signInWithApple(idToken: cred.idToken, nonce: cred.nonce)
                if let me = supabase.currentUserId {
                    await purchases.identify(supabaseUserId: me)
                }
                await pairing.consumeDeferredInviteIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
