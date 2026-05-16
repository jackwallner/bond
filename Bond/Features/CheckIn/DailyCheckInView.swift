import SwiftUI

struct DailyCheckInView: View {
    @Environment(DailyCheckInService.self) private var checkIn
    @Environment(PurchasesService.self) private var store
    @Environment(PairingService.self) private var pairing
    @State private var responseText = ""
    @State private var isPaywallPresented = false
    @State private var hasSubmitted = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPremium {
                    gate
                } else if pairing.solo {
                    soloState
                } else if checkIn.isLoading && checkIn.todaysQuestion == nil {
                    ProgressView("Loading today's question...")
                } else {
                    content
                }
            }
            .navigationTitle("Check-In")
            .paywallSheet(isPresented: $isPaywallPresented)
            .task {
                if store.isPremium && !pairing.solo {
                    await checkIn.loadTodaysQuestion()
                }
            }
        }
    }

    private var gate: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("Daily Check-In is a premium feature")
                .font(.headline)
            Text("Answer a daily question together with your partner and discover what makes your relationship stronger.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Unlock Premium") { isPaywallPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
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
            VStack(spacing: 24) {
                // Question card
                VStack(spacing: 12) {
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(lang.tint.opacity(0.12), in: Capsule())
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                // My response
                if let myResponse = checkIn.myResponse {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Your answer")
                                .font(.subheadline.bold())
                        }
                        Text(myResponse.response)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Partner response
                    if let partnerResponse = checkIn.partnerResponse {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(.pink)
                                Text("Your partner's answer")
                                    .font(.subheadline.bold())
                            }
                            Text(partnerResponse.response)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Waiting for your partner to answer...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    // Answer input
                    VStack(spacing: 12) {
                        TextField("Type your answer...", text: $responseText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .padding()
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                        Button {
                            Task {
                                await checkIn.submitResponse(responseText)
                                if checkIn.myResponse != nil {
                                    hasSubmitted = true
                                    responseText = ""
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if checkIn.isLoading {
                                    ProgressView()
                                } else {
                                    Text("Submit Answer")
                                        .font(.headline)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(responseText.trimmingCharacters(in: .whitespaces).isEmpty || checkIn.isLoading)
                    }
                }
            }
            .padding()
        }
    }
}
