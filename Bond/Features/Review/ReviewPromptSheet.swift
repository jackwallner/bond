import SwiftUI
import UIKit

/// Feedback is its own path, never a branch of a rating question. Guideline
/// 5.6.1 rejects any flow that asks how someone feels and only sends the happy
/// ones to the App Store, so ratings go straight to Apple's own prompt.
@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    @Published var feedbackRequested = false

    private init() {}

    func requestFeedback() {
        feedbackRequested = true
    }

    func clear() {
        feedbackRequested = false
    }
}

enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case feedbackSubmitted
}

struct ReviewPromptSheet: View {
    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        NavigationStack {
            feedbackContent
                .navigationTitle("Help us improve")
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(Color.bondBackgroundGradient.ignoresSafeArea())
    }

    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What would make Little Gestures work better for you?")
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
            URLQueryItem(name: "subject", value: "Little Gestures feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
