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
    /// Split, the tab bar may float over the leading pane's bottom, so the hard
    /// edge backs it instead of letting rows read through. Bar placement is
    /// left to the system: forcing horizontal bars with
    /// `toolbarVerticalBehavior(.disabled)` inset the whole app 42 pt from
    /// both edges of the inner display and left white strips there.
    @ViewBuilder
    func unfoldedBars(isSplit: Bool) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(isSplit ? .hard : nil, for: .bottom)
        } else {
            self
        }
    }
}

extension View {
    /// The Insights pane's navigation bar in the same horizontal form as the
    /// tab pane beside it. Split, the tab pane gets a horizontal bar with a
    /// row above each large title, while Insights took the vertical
    /// behaviour with no row, so its title sat 57 pt higher. Scoped to the
    /// pane: disabling
    /// vertical bars on the whole root inset the app from both display edges.
    @ViewBuilder
    func horizontalNavigationBar() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
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

extension EnvironmentValues {
    /// True while the unfolded display is split into two panes. Set once at
    /// the root by `unfoldedSplitEnvironment()`; pane contents report a
    /// compact width, so they can't tell on their own.
    @Entry var isUnfoldedSplit = false
}

/// Measures the root and publishes `isUnfoldedSplit` to everything below it,
/// including the sheets the root and its panes present.
private struct UnfoldedSplitEnvironment: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var geometry = PaneGeometry()

    func body(content: Content) -> some View {
        content
            .environment(\.isUnfoldedSplit, UnfoldedSplit.make(
                width: geometry.width,
                isRegularWidth: horizontalSizeClass == .regular,
                fold: geometry.fold
            ) != nil)
            .onGeometryChange(for: PaneGeometry.self) { proxy in
                PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
            } action: { geometry = $0 }
    }
}

/// A sheet that never straddles the fold. A system sheet on the unfolded
/// display is centred, which puts the fold through the middle of the form, so
/// while split it covers the display instead, with its content in the leading
/// pane and the brand beside it, as onboarding does. Everywhere else it is the
/// ordinary sheet. A fold or unfold mid-presentation re-presents it in the
/// other style.
private struct UnfoldedSheet<SheetContent: View>: ViewModifier {
    @Environment(\.isUnfoldedSplit) private var isSplit
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isSplit ? .constant(false) : $isPresented, onDismiss: onDismiss) {
                sheetContent()
            }
            .fullScreenCover(isPresented: isSplit ? $isPresented : .constant(false), onDismiss: onDismiss) {
                sheetContent()
                    .unfoldedLeadingPane { UnfoldedBrandPanel() }
                    .background(Color.bondBackgroundGradient.ignoresSafeArea())
            }
    }
}

extension View {
    func unfoldedSplitEnvironment() -> some View {
        modifier(UnfoldedSplitEnvironment())
    }

    func unfoldedSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(UnfoldedSheet(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    func unfoldedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        unfoldedSheet(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            onDismiss: onDismiss
        ) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}
