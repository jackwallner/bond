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
                    .foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents(step == .feedback ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .background(Color.bondBackgroundGradient.ignoresSafeArea())
    }

    private var navigationTitle: String {
        switch step {
        case .enjoyment: "Enjoying Bond?"
        case .reviewPitch: "Support an indie app"
        case .feedback: "Help us improve"
        }
    }

    private var enjoymentContent: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.bondAccent.gradient)
                    .frame(width: 64, height: 64)
                Image(systemName: "heart.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            Text("If Bond is helping you show up for your partner, a quick App Store rating helps more couples find gentle love-language reminders.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Button { step = .reviewPitch } label: {
                    primaryButtonLabel("Yes, I'm enjoying it")
                }
                .buttonStyle(.plain)

                Button { step = .feedback } label: {
                    secondaryButtonLabel("Not really")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var reviewPitchContent: some View {
        VStack(spacing: 18) {
            Text("Bond is built by one indie developer. No ads, no accounts beyond sign-in, and your reminders stay between you and your partner.")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("An honest App Store review takes seconds and helps more couples discover a calm way to nurture their relationship.")
                .font(.bond(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button {
                    ReviewPromptTracker.markOpenedWriteReview()
                    if let url = AppStoreReviewLinks.writeReviewURL {
                        UIApplication.shared.open(url)
                    }
                    finish(.openedWriteReview)
                } label: {
                    primaryButtonLabel("Rate on the App Store")
                }
                .buttonStyle(.plain)
                .disabled(AppStoreReviewLinks.writeReviewURL == nil)

                Button {
                    ReviewPromptTracker.markShown()
                    finish(.enjoyedMaybeLater)
                } label: {
                    secondaryButtonLabel("Maybe later")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What would make Bond work better for you?")
                .font(.bond(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $feedbackText)
                .font(.bond(.body))
                .frame(minHeight: 140)
                .padding(10)
                .background(Color.bondSurface, in: RoundedRectangle(cornerRadius: 12))
                .focused($feedbackFocused)

            Text("Opens your mail app with a draft to the developer. No analytics, just your words.")
                .font(.bond(.caption))
                .foregroundStyle(.secondary)

            Button { sendFeedback() } label: {
                primaryButtonLabel("Send feedback")
            }
            .buttonStyle(.plain)
            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear { feedbackFocused = true }
    }

    private func primaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.bond(.headline, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.bondAccent.gradient, in: Capsule())
    }

    private func secondaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.bond(.subheadline, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
