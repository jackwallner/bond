import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PurchasesService.self) private var purchases
    @State private var appleHelper = AppleSignInHelper()
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.pink.gradient)

                Text("Bond")
                    .font(.largeTitle.bold())

                Text("Small acts of love, on cue.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { _ in
                // Routed through AppleSignInHelper below for nonce/JWT control.
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal)
            .overlay {
                Button {
                    Task { await signIn() }
                } label: {
                    Color.clear
                }
            }
            .disabled(isSigningIn)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 48)
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let result = try await appleHelper.performSignIn()
            try await supabase.signInWithApple(idToken: result.idToken, nonce: result.nonce)
            if let me = supabase.currentUserId {
                await purchases.identify(supabaseUserId: me)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
