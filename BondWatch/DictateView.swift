import SwiftUI

struct DictateView: View {
    private let sender = WatchConnectivitySender.shared

    @State private var text = ""
    @State private var language: LoveLanguage = .words
    @State private var recipient: WatchPayload.Recipient = .partner
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TextField("Dictate a reminder", text: $text, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                Picker("For", selection: $recipient) {
                    Text("My partner").tag(WatchPayload.Recipient.partner)
                    Text("Me").tag(WatchPayload.Recipient.me)
                }
                .pickerStyle(.navigationLink)

                Picker("Language", selection: $language) {
                    ForEach(LoveLanguage.allCases) { l in
                        Text(l.title).tag(l)
                    }
                }
                .pickerStyle(.navigationLink)

                Button("Send") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .navigationTitle("New")
    }

    private func send() async {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let outcome = await sender.sendDictatedReminder(
            title: cleaned, language: language, recipient: recipient
        )
        switch outcome {
        case .confirmed:
            statusMessage = "Saved — you'll be reminded in about an hour."
            text = ""
        case .queued:
            statusMessage = "Queued — open Bond on your phone to confirm."
            text = ""
        case .failed:
            statusMessage = sender.lastError ?? "Send failed."
        }
    }
}
