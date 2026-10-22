import SwiftUI

/// Pane frames for the unfolded iPhone Duo: the tabs on the leading side of the
/// fold, Insights on the trailing side, so nothing straddles the crease. `nil`
/// keeps the single column (every ordinary iPhone, the folded Duo, and the
/// unfolded Duo held in portrait, where each half would be too narrow).
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the compact Reminders and Insights layouts.
    static let minimumPaneWidth: CGFloat = 360

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// The container's width and fold, measured together so one geometry change
/// moves both panes.
struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat = 0
    var fold: ClosedRange<CGFloat>?
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}

extension View {
    /// Split, the panes run to the display's edges. The inner display insets
    /// the scene 42 pt each side, and a pane's stack painted that inset white
    /// beside the warm wash. Folded keeps every inset (the outer display's
    /// vertical bar lives in one). Measure the split inside this modifier.
    func unfoldedFullBleed(isSplit: Bool) -> some View {
        ignoresSafeArea(.container, edges: isSplit ? .horizontal : [])
    }

    /// Split, each pane keeps its bars horizontal: iOS 27.1 otherwise moves a
    /// stack's toolbar into a vertical bar on its trailing edge, which in the
    /// leading pane sits against the fold and narrows the screen. The tab bar
    /// then floats over the leading pane's bottom, so the hard edge backs it
    /// instead of letting rows read through. Folded keeps the system default.
    @ViewBuilder
    func unfoldedBars(isSplit: Bool) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(isSplit ? .disabled : .automatic)
                .scrollEdgeEffectStyle(isSplit ? .hard : nil, for: .bottom)
        } else if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(isSplit ? .hard : nil, for: .bottom)
        } else {
            self
        }
    }
}

/// Keeps a single-column screen (onboarding, pairing success) on the leading
/// side of the fold and puts `trailing` in the other pane. Every other width
/// shows the screen as it is. Only frames change, so a fold mid-step keeps the
/// screen's state.
private struct UnfoldedLeadingPane<Trailing: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var geometry = PaneGeometry()
    let trailing: Trailing

    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(width: geometry.width, isRegularWidth: horizontalSizeClass == .regular, fold: geometry.fold)
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .environment(\.horizontalSizeClass, split == nil ? horizontalSizeClass : .compact)
                .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)
            trailing
                .frame(width: split?.secondaryWidth ?? 0)
                .frame(maxHeight: .infinity)
                .padding(.leading, split?.secondaryX ?? 0)
                .opacity(split == nil ? 0 : 1)
                .accessibilityHidden(split == nil)
        }
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { geometry = $0 }
        .unfoldedFullBleed(isSplit: split != nil)
        .unfoldedBars(isSplit: split != nil)
    }
}

extension View {
    func unfoldedLeadingPane<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(UnfoldedLeadingPane(trailing: trailing()))
    }
}

/// What the trailing pane shows beside onboarding: the brand, so the open
/// display reads as one product rather than a phone screen and a blank half.
struct UnfoldedBrandPanel: View {
    var body: some View {
        BondHero(subtitle: "Small, timely reminders of what your partner actually appreciates.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
