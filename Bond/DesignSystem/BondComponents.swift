import SwiftUI

// Reusable views shared across the redesigned screens.

struct BondHero: View {
    var subtitle: String?

    var body: some View {
        VStack(spacing: BondSpacing.base) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.bondAccent.gradient)
                .accessibilityHidden(true)
            Text("Bond")
                .font(.largeTitle.bold())
                .tracking(-0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BondSpacing.xl)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "Bond. \($0)" } ?? "Bond")
    }
}

struct BondScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.xs) {
            Text(title).font(.title.bold())
            if let subtitle {
                Text(subtitle).font(.body).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BondPrimaryButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: BondSpacing.s) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(role == .destructive ? .red : .bondAccent)
        .controlSize(.large)
        .disabled(isLoading)
    }
}

struct BondInlineError: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.footnote)
        .foregroundStyle(.red)
        .padding(.horizontal, BondSpacing.base)
        .accessibilityLabel("Error: \(message)")
    }
}

struct BondChoiceCard<Trailing: View>: View {
    let symbol: String
    let title: String
    let description: String
    var tint: Color = .secondary
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    init(
        symbol: String,
        title: String,
        description: String,
        tint: Color = .secondary,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.description = description
        self.tint = tint
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: BondSpacing.base) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: BondSpacing.xs) {
                    Text(title).font(.headline)
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: BondSpacing.s)
                trailing()
            }
            .padding(BondSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: BondRadius.card)
                    .stroke(Color.bondHairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap to choose")
    }
}

struct BondSealedCard: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: BondSpacing.s) {
            HStack(spacing: BondSpacing.s) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.secondary)
                Text(title).font(.subheadline.bold())
                Spacer()
            }
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(BondSpacing.base)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
        .overlay(
            RoundedRectangle(cornerRadius: BondRadius.inline)
                .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                .foregroundStyle(.secondary.opacity(0.4))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(hint).")
    }
}
