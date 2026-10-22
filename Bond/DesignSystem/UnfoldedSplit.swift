import SwiftUI
import UIKit

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

/// Paints the window behind the app with the warm wash. The unfolded iPhone
/// Duo lays the app out 42 pt in from each side of the inner display, and the
/// window's default white showed in those strips beside the panes. A one
/// point wide gradient tiles across the window, so the edges match the wash.
struct WindowWash: UIViewRepresentable {
    func makeUIView(context: Context) -> WashView { WashView() }
    func updateUIView(_ view: WashView, context: Context) { view.paint() }

    final class WashView: UIView {
        private var painted: (height: CGFloat, style: UIUserInterfaceStyle)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: WashView, _) in
                view.paint()
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            paint()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            paint()
        }

        func paint() {
            guard let window, window.bounds.height > 0 else { return }
            let traits = window.traitCollection
            let height = window.bounds.height
            guard painted?.height != height || painted?.style != traits.userInterfaceStyle else { return }
            let colors = [Color.bondWashTop, Color.bondWashBottom].map {
                UIColor($0).resolvedColor(with: traits).cgColor
            }
            guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil) else { return }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: height)).image { context in
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: 0, y: height), options: []
                )
            }
            window.backgroundColor = UIColor(patternImage: image)
            painted = (height, traits.userInterfaceStyle)
        }
    }
}
