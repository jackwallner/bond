import SwiftUI
import UIKit

@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    enum Presentation {
        case enjoymentPrompt
        case feedbackOnly
    }

    @Published var pendingPresentation: Presentation?

    private init() {}

    func requestEnjoymentPrompt() {
        pendingPresentation = .enjoymentPrompt
    }

    func requestFeedback() {
        pendingPresentation = .feedbackOnly
    }

    func clear() {
        pendingPresentation = nil
    }
}

enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case feedbackSubmitted
    case openedWriteReview
    case enjoyedMaybeLater
}

struct ReviewPromptSheet: View {
    enum Step {
        case enjoyment
        case reviewPitch
        case feedback
    }

    let initialStep: Step
    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    init(initialStep: Step = .enjoyment, onFinish: @escaping (ReviewPromptDismissOutcome) -> Void) {
        self.initialStep = initialStep
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .enjoyment:
                    enjoymentContent
                case .reviewPitch:
                    reviewPitchContent
                case .feedback:
                    feedbackContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        handleNotNow()
                    }
                }
            }
        }
        .presentationDetents(step == .feedback ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var navigationTitle: String {
        switch step {
        case .enjoyment: "Enjoying Bond?"
        case .reviewPitch: "Support an indie dev"
        case .feedback: "Help us improve"
        }
    }

    private var enjoymentContent: some View {
        VStack(spacing: BondSpacing.l) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.bondAccent.gradient)
                .padding(.top, BondSpacing.s)

            Text("If Bond is helping you show up for your relationship, a quick App Store rating makes a real difference.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BondSpacing.s)

            VStack(spacing: BondSpacing.s) {
                BondPrimaryButton(title: "Yes, I'm enjoying it") {
                    step = .reviewPitch
                }
                Button("Not really") {
                    step = .feedback
                }
                .font(.bond(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, BondSpacing.xl)
        .padding(.bottom, BondSpacing.xl)
    }

    private var reviewPitchContent: some View {
        VStack(spacing: BondSpacing.m) {
            Text("Bond is built by one indie developer. No ads, no data selling, and your relationship stays between you and your partner.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, BondSpacing.s)

            Text("An honest App Store review takes seconds and helps more couples find a simple reminder app.")
                .font(.bond(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: BondSpacing.s) {
                if AppStoreReviewLinks.writeReviewURL != nil {
                    BondPrimaryButton(title: "Rate on the App Store") {
                        guard let url = AppStoreReviewLinks.writeReviewURL else { return }
                        ReviewPromptTracker.markOpenedWriteReview()
                        UIApplication.shared.open(url)
                        finish(.openedWriteReview)
                    }
                } else {
                    Text("App Store rating will be available once Bond is live on the App Store.")
                        .font(.bond(.caption))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                Button("Maybe later") {
                    ReviewPromptTracker.markShown()
                    finish(.enjoyedMaybeLater)
                }
                .font(.bond(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, BondSpacing.xl)
        .padding(.bottom, BondSpacing.xl)
    }

    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: BondSpacing.m) {
            Text("What would make Bond work better for you?")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $feedbackText)
                .font(.bond(.body))
                .frame(minHeight: 140)
                .padding(BondSpacing.s)
                .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                .focused($feedbackFocused)

            Text("Opens your mail app with a draft to the developer.")
                .font(.bond(.caption))
                .foregroundStyle(.secondary)

            BondPrimaryButton(
                title: "Send feedback",
                isLoading: false
            ) {
                sendFeedback()
            }
            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, BondSpacing.xl)
        .padding(.bottom, BondSpacing.xl)
        .onAppear { feedbackFocused = true }
    }

    private func handleNotNow() {
        ReviewPromptTracker.markShown()
        finish(.notNow)
    }

    private func sendFeedback() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = Self.feedbackMailURL(body: trimmed) else { return }
        ReviewPromptTracker.markFeedbackSubmitted()
        UIApplication.shared.open(url)
        finish(.feedbackSubmitted)
    }

    private func finish(_ outcome: ReviewPromptDismissOutcome) {
        onFinish(outcome)
        dismiss()
    }

    static func feedbackMailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "jackwallner+b@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Bond feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
