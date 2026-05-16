import CoreImage.CIFilterBuiltins
import SwiftUI

struct PairingView: View {
    @Environment(PairingService.self) private var pairing

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
            .navigationTitle("Pair")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { _, new in
                if new == .receive { isCodeFocused = true }
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
