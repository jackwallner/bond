import SwiftUI

struct PreferenceChoiceView: View {
    @Environment(PairingService.self) private var pairing

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.pink.gradient)

                Text("Bond")
                    .font(.largeTitle.bold())
            }

            Text("How will you use Bond?")
                .font(.title2.bold())

            VStack(spacing: 16) {
                Button {
                    Task { await pairing.createSoloCouple() }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 36))
                        Text("Just me")
                            .font(.headline)
                        Text("Set reminders for yourself. Journal, self-care, habits — whatever helps you grow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button {
                    pairing.needsPreferenceChoice = false
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 36))
                        Text("With someone")
                            .font(.headline)
                        Text("Share reminders with your partner. Little nudges of love, surprises, and milestones together.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            if let error = pairing.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical, 48)
    }
}
