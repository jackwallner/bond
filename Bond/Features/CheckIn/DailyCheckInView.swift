import SwiftUI
import UIKit

struct DailyCheckInView: View {
    @Environment(DailyCheckInService.self) private var checkIn
    @Environment(PurchasesService.self) private var store
    @Environment(PairingService.self) private var pairing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var responseText = ""
    @State private var isPaywallPresented = false
    @State private var hasSubmitted = false
    @State private var revealPhase: RevealPhase = .sealed

    enum RevealPhase { case sealed, revealing, revealed }

    var body: some View {
        NavigationStack {
            Group {
                if pairing.solo {
                    soloState
                } else if checkIn.isLoading && checkIn.todaysQuestion == nil {
                    ProgressView("Loading today's question...")
                } else if !store.isPremium {
                    teaserContent
                } else {
                    content
                }
            }
            .navigationTitle("Check-In")
            .paywallSheet(isPresented: $isPaywallPresented)
            .task {
                if !pairing.solo {
                    await checkIn.loadTodaysQuestion()
                }
            }
        }
    }

    /// Free, paired users see today's real question — the answer flow stays
    /// paywalled. Question text alone isn't sensitive: the value of Premium
    /// is in the back-and-forth, not in knowing the prompt.
    private var teaserContent: some View {
        ScrollView {
            VStack(spacing: BondSpacing.xl) {
                questionCard
                BondCheckInUnlockCard(isPaywallPresented: $isPaywallPresented)
            }
            .padding()
        }
    }

    private var soloState: some View {
        ContentUnavailableView(
            "For Couples Only",
            systemImage: "person.fill.questionmark",
            description: Text("Daily Check-In is designed for couples to share and compare answers. Pair up with someone to get started.")
        )
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: BondSpacing.xl) {
                questionCard

                if let myResponse = checkIn.myResponse {
                    answerBlock(
                        title: "Your answer",
                        icon: "person.circle.fill",
                        tint: .blue,
                        text: myResponse.response
                    )

                    if let partnerResponse = checkIn.partnerResponse {
                        partnerCard(partnerResponse.response)
                    } else {
                        BondSealedCard(
                            title: "Their answer",
                            hint: "Sealed until they answer"
                        )
                    }
                } else {
                    answerInput
                }
            }
            .padding()
        }
        .onChange(of: checkIn.partnerResponse?.response) { _, new in
            guard new != nil, checkIn.myResponse != nil else { return }
            runRevealIfNeeded()
        }
        .onAppear {
            if checkIn.myResponse != nil && checkIn.partnerResponse != nil {
                runRevealIfNeeded()
            }
        }
    }

    private var questionCard: some View {
        VStack(spacing: BondSpacing.m) {
            if let question = checkIn.todaysQuestion {
                if let lang = question.loveLanguage {
                    Image(systemName: lang.symbolName)
                        .font(.title)
                        .foregroundStyle(lang.tint)
                }
                Text(question.question)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if let lang = question.loveLanguage {
                    Text(lang.title)
                        .font(.caption)
                        .foregroundStyle(lang.tint)
                        .padding(.horizontal, BondSpacing.m)
                        .padding(.vertical, BondSpacing.xs)
                        .background(lang.tint.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card))
    }

    private func answerBlock(
        title: String, icon: String, tint: Color, text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: BondSpacing.s) {
            HStack(spacing: BondSpacing.s) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline.bold())
            }
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: BondRadius.inline))
        }
    }

    private func partnerCard(_ text: String) -> some View {
        ZStack {
            if revealPhase == .sealed {
                BondSealedCard(title: "Their answer", hint: "Sealed until they answer")
                    .transition(.opacity)
            } else {
                answerBlock(
                    title: "Their answer",
                    icon: "person.circle.fill",
                    tint: .bondAccent,
                    text: text
                )
                .opacity(revealPhase == .revealed ? 1 : 0)
                .transition(.opacity)
            }
        }
    }

    private var answerInput: some View {
        VStack(spacing: BondSpacing.m) {
            TextField("Type your answer...", text: $responseText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding()
                .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))

            BondPrimaryButton(
                title: "Submit answer",
                isLoading: checkIn.isLoading
            ) {
                Task {
                    await checkIn.submitResponse(responseText)
                    if checkIn.myResponse != nil {
                        hasSubmitted = true
                        responseText = ""
                    }
                }
            }
            .disabled(responseText.trimmingCharacters(in: .whitespaces).isEmpty || checkIn.isLoading)
        }
    }

    private func runRevealIfNeeded() {
        let key = "reveal-shown-\(Self.dayKey())"
        if UserDefaults.standard.bool(forKey: key) {
            revealPhase = .revealed
            return
        }
        UserDefaults.standard.set(true, forKey: key)

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { revealPhase = .revealed }
            announceReveal()
            return
        }

        revealPhase = .sealed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.35)) { revealPhase = .revealing }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeOut(duration: 0.40)) { revealPhase = .revealed }
            announceReveal()
        }
    }

    private func announceReveal() {
        let who = pairing.partnerProfile?.displayName ?? "They"
        UIAccessibility.post(notification: .announcement, argument: "\(who) answered.")
    }

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
