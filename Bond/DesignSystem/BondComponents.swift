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
                .font(.bond(.largeTitle, weight: .bold))
                .tracking(-0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.bond(.title3))
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
            Text(title).font(.bond(.title, weight: .bold))
            if let subtitle {
                Text(subtitle).font(.bond(.body)).foregroundStyle(.secondary)
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
                    Text(title).font(.bond(.headline))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(BondSoftButtonStyle(role: role))
        .disabled(isLoading)
    }
}

/// Soft Tactile primary button: top-lit gradient fill, warm halo shadow, and
/// a faint top highlight so it reads as a raised physical control. Presses
/// dim + sink slightly rather than flashing a system tint. When disabled it
/// desaturates and flattens (no shadow) so it visibly reads as inactive —
/// otherwise a `.disabled()` CTA looked fully tappable and a tap did nothing.
struct BondSoftButtonStyle: ButtonStyle {
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, role: role)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let role: ButtonRole?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, BondSpacing.l)
                .background {
                    let shape = RoundedRectangle(cornerRadius: BondRadius.inline, style: .continuous)
                    ZStack {
                        if role == .destructive {
                            shape.fill(
                                LinearGradient(colors: [Color.red.opacity(0.92), .red],
                                               startPoint: .top, endPoint: .bottom)
                            )
                        } else {
                            shape.fill(Color.bondAccentGradient)
                        }
                        // Inset top highlight — the "lit from above" cue.
                        shape.stroke(.white.opacity(0.25), lineWidth: 0.5)
                            .blur(radius: 0.5)
                            .mask(LinearGradient(colors: [.white, .clear],
                                                 startPoint: .top, endPoint: .center))
                    }
                }
                .saturation(isEnabled ? 1 : 0)
                .shadow(color: .bondShadow,
                        radius: isEnabled ? (pressed ? 4 : 12) : 0,
                        x: 0, y: isEnabled ? (pressed ? 2 : 7) : 0)
                .scaleEffect(pressed ? 0.98 : 1)
                .opacity(isEnabled ? (pressed ? 0.92 : 1) : 0.45)
                .animation(.easeOut(duration: 0.15), value: pressed)
                .animation(.easeOut(duration: 0.15), value: isEnabled)
        }
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
        .font(.bond(.footnote))
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
                    Text(title).font(.bond(.headline))
                    Text(description).font(.bond(.subheadline)).foregroundStyle(.secondary)
                }
                Spacer(minLength: BondSpacing.s)
                trailing()
            }
            .padding(BondSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.card, style: .continuous))
            .bondSoftElevation()
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
                Text(title).font(.bond(.subheadline, weight: .bold))
                Spacer()
            }
            Text(hint)
                .font(.bond(.callout))
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
