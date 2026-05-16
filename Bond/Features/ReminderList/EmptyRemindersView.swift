import SwiftUI

struct StarterChip: Identifiable {
    let id = UUID()
    let title: String
    let loveLanguage: LoveLanguage
}

let starterChips: [StarterChip] = [
    StarterChip(title: "Tell them they're beautiful", loveLanguage: .words),
    StarterChip(title: "Ten-minute walk together", loveLanguage: .time),
    StarterChip(title: "Bring home flowers", loveLanguage: .gifts),
    StarterChip(title: "A long hug at the door", loveLanguage: .touch)
]

struct EmptyRemindersView: View {
    let onTapChip: (StarterChip) -> Void
    let onBrowseTemplates: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: BondSpacing.xxxl)

                VStack(spacing: BondSpacing.m) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No reminders yet.")
                        .font(.title3.bold())
                    Text("Add one with the + button, or start with these.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BondSpacing.xl)
                }

                Spacer().frame(height: BondSpacing.xxl)

                VStack(alignment: .leading, spacing: BondSpacing.m) {
                    Text("Start here")
                        .font(.subheadline.bold())
                    ForEach(starterChips) { chip in
                        Button { onTapChip(chip) } label: {
                            HStack(spacing: BondSpacing.m) {
                                Image(systemName: chip.loveLanguage.symbolName)
                                    .font(.body)
                                    .foregroundStyle(chip.loveLanguage.tint)
                                    .frame(width: 24)
                                Text(chip.title)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, BondSpacing.base)
                            .padding(.vertical, BondSpacing.m)
                            .background(Color.bondCardFill, in: RoundedRectangle(cornerRadius: BondRadius.inline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Double-tap to start a reminder")
                    }
                }
                .padding(.horizontal, BondSpacing.base)

                Button(action: onBrowseTemplates) {
                    HStack(spacing: BondSpacing.xs) {
                        Text("Browse templates")
                        Image(systemName: "arrow.right")
                    }
                    .font(.footnote.bold())
                    .foregroundStyle(Color.bondAccent)
                }
                .padding(.top, BondSpacing.base)

                Spacer()
            }
        }
    }
}

struct FilteredEmptyView: View {
    let onShowAll: () -> Void

    var body: some View {
        VStack(spacing: BondSpacing.base) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing for you right now.")
                .font(.headline)
            Text("Your partner is the lucky one today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Show all reminders", action: onShowAll)
                .buttonStyle(.bordered)
                .tint(.bondAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BondSpacing.xxl)
        .listRowBackground(Color.clear)
    }
}
