import AuthenticationServices
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PairingView: View {
    @Environment(PairingService.self) private var pairing
    @Environment(SupabaseService.self) private var supabase

    enum PairMode: String, CaseIterable { case send, receive
        var title: String { self == .send ? "Send" : "Receive" }
    }

    @State private var mode: PairMode = .send
    @State private var manualCode = ""
    @State private var isGenerating = false
    @State private var showQR = false
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if supabase.isAnonymous {
                    AppleSignInPairingGate()
                } else {
                    pairContent
                }
            }
            .navigationTitle("Pair")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { _, new in
                if new == .receive { isCodeFocused = true }
            }
        }
    }

    private var pairContent: some View {
        VStack(spacing: 0) {
            Picker("Pairing mode", selection: $mode) {
                ForEach(PairMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, BondSpacing.base)
            .padding(.bottom, BondSpacing.base)

            ScrollView {
                switch mode {
                case .send:    sendContent
                case .receive: receiveContent
                }
            }
        }
    }

    // MARK: - Send (host)

    private var sendContent: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "Invite your partner",
                subtitle: "Send them this link, or read them the code below."
            )
            .padding(.horizontal, BondSpacing.base)

            CodeCard(code: pairing.pendingInviteCode ?? "------")
                .padding(.horizontal, BondSpacing.base)

            if let expiresAt = pairing.pendingInviteExpiresAt {
                ExpiryCaption(expiresAt: expiresAt)
                    .padding(.horizontal, BondSpacing.base)
            }

            if let url = pairing.pendingInviteURL {
                ShareLink(
                    item: url,
                    subject: Text("I want to pair with you on Bond."),
                    message: Text("I'm using Bond — a small app for sending each other little reminders. Tap the link to pair with me, or use the code: \(pairing.pendingInviteCode ?? "").")
                ) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bondAccent)
                .controlSize(.large)
                .padding(.horizontal, BondSpacing.base)

                DisclosureGroup(isExpanded: $showQR) {
                    VStack(spacing: BondSpacing.s) {
                        QRCodeView(string: url.absoluteString)
                            .padding(.top, BondSpacing.s)
                        Text("In the same room? Have them point their camera at this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } label: {
                    Label("Show QR code", systemImage: "qrcode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, BondSpacing.base)
            } else {
                BondPrimaryButton(
                    title: "Generate code",
                    systemImage: "link.badge.plus",
                    isLoading: isGenerating
                ) {
                    Task {
                        isGenerating = true
                        defer { isGenerating = false }
                        _ = await pairing.generateInviteCode()
                    }
                }
                .padding(.horizontal, BondSpacing.base)
            }

            if let err = pairing.lastError {
                BondInlineError(message: err)
            }
        }
        .padding(.vertical, BondSpacing.l)
    }

    // MARK: - Receive (guest)

    private var receiveContent: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xl) {
            BondScreenHeader(
                title: "Enter their code",
                subtitle: "Six characters. Your partner can read it to you."
            )
            .padding(.horizontal, BondSpacing.base)

            CodeEntryField(text: $manualCode, isFocused: $isCodeFocused)
                .padding(.horizontal, BondSpacing.base)

            BondPrimaryButton(title: "Pair", isLoading: pairing.isPairing) {
                Task { await pairing.consumeInviteCode(manualCode.uppercased()) }
            }
            .padding(.horizontal, BondSpacing.base)
            .disabled(manualCode.count < 6)

            if let err = pairing.lastError {
                BondInlineError(message: err)
            }
        }
        .padding(.vertical, BondSpacing.l)
    }
}

// MARK: - Code card (host display)

private struct CodeCard: View {
    let code: String

    var body: some View {
        HStack(spacing: BondSpacing.s) {
            ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .frame(width: 44, height: 56)
                    .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BondSpacing.base)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BondRadius.hero))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pairing code: \(code.map(String.init).joined(separator: " "))")
    }
}

// MARK: - Expiry caption (live countdown)

private struct ExpiryCaption: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let remaining = expiresAt.timeIntervalSince(context.date)
            Group {
                if remaining <= 0 {
                    Text("Expired. Generate a new code.")
                } else {
                    let hours = Int(remaining) / 3600
                    let minutes = (Int(remaining) % 3600) / 60
                    Text("Expires in \(hours)h \(minutes)m")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Code entry (guest input)

private struct CodeEntryField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    private let allowed = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    var body: some View {
        ZStack {
            TextField("", text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused(isFocused)
                .opacity(0.02)
                .onChange(of: text) { _, new in
                    let cleaned = new.uppercased().filter { allowed.contains($0) }
                    let trimmed = String(cleaned.prefix(6))
                    if trimmed != text { text = trimmed }
                }

            HStack(spacing: BondSpacing.s) {
                let chars = Array(text.prefix(6))
                ForEach(0..<6, id: \.self) { i in
                    let char = i < chars.count ? String(chars[i]) : ""
                    let isCaret = i == chars.count && isFocused.wrappedValue
                    Text(char)
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .frame(width: 44, height: 56)
                        .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                        .overlay(
                            RoundedRectangle(cornerRadius: BondRadius.inline)
                                .strokeBorder(isCaret ? Color.bondAccent : Color.clear, lineWidth: 1.5)
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code entry, six characters. \(text.count) of 6 entered.")
    }
}

// MARK: - QR

private struct QRCodeView: View {
    let string: String

    var body: some View {
        if let image = Self.qr(from: string) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .padding(BondSpacing.base)
                .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card))
                .accessibilityLabel("QR code containing your invite link")
                .accessibilityHint("Your partner can scan this with their camera.")
        }
    }

    private static func qr(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        ),
        let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Apple Sign-In gate

/// Surfaces Apple Sign-In as the price of admission for pairing. Anonymous
/// users get to use the rest of the app without an account, but pairing
/// requires a recoverable identity so their partner can keep reaching them
/// across reinstalls and device swaps. Supabase promotes the anonymous user
/// to a permanent Apple-linked user in place — no data migration needed.
struct AppleSignInPairingGate: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(PurchasesService.self) private var purchases
    @Environment(\.colorScheme) private var colorScheme
    @State private var appleHelper = AppleSignInHelper()
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: BondSpacing.xl) {
            Spacer()
            VStack(spacing: BondSpacing.m) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.bondAccent)
                Text("Sign in to pair")
                    .font(.title2.bold())
                Text("Pairing connects your reminders with your partner's. Apple Sign-In keeps that link recoverable across devices.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BondSpacing.xl)
            }

            VStack(spacing: BondSpacing.m) {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.large)
                        .frame(height: 50)
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
            }

            Spacer()
        }
        .padding(.vertical, BondSpacing.xxxl)
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
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
