import SwiftUI

struct PairingView: View {
    @Environment(PairingService.self) private var pairing
    @State private var inviteURL: URL?
    @State private var manualCode = ""
    @State private var isGenerating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pair with your partner")
                        .font(.title2.bold())
                    Text("Send them a link or share a 6-character code. One of you generates, the other accepts.")
                        .foregroundStyle(.secondary)
                }

                Section("Invite your partner") {
                    if let inviteURL {
                        Text(inviteURL.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        if let code = pairing.pendingInviteCode {
                            Text("Code: \(code)")
                                .font(.title.monospaced().bold())
                                .frame(maxWidth: .infinity)
                        }
                        ShareLink(
                            item: inviteURL,
                            subject: Text("You've been invited to Bond 💕"),
                            message: Text("Someone special wants to pair up with you on Bond! Open the link and let the love reminders begin. 💌")
                        ) {
                            Label("Share with partner", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await generate() }
                        } label: {
                            if isGenerating {
                                ProgressView()
                            } else {
                                Label("Generate invite link", systemImage: "link.badge.plus")
                            }
                        }
                        .disabled(isGenerating)
                    }
                }

                Section("Have a code?") {
                    TextField("ABC123", text: $manualCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                    Button("Pair") {
                        Task { await pairing.consumeInviteCode(manualCode.uppercased()) }
                    }
                    .disabled(manualCode.count < 6)
                }

                if let lastError = pairing.lastError {
                    Section {
                        Text(lastError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Pair")
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        inviteURL = await pairing.generateInviteCode()
    }
}
