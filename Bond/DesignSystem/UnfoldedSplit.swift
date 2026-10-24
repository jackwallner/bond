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

/// Heights for the leading pane's clearance above its floating tab bar.
/// Split, content ends `gap` above the bar's safe-area edge, and a bottom
/// scroll content margin of `gap` lets the last row scroll up to that line.
/// Folded, both are zero and the phone layout is untouched.
struct TabBarClearance: Equatable, Sendable {
    /// Masked out from the bottom: the bar's inset plus the gap.
    var hidden: CGFloat
    /// Bottom scroll content margin, so a scrolled-to-end row meets the line.
    var contentPadding: CGFloat

    static let gap: CGFloat = 12

    static func make(isSplit: Bool, barInset: CGFloat) -> TabBarClearance {
        guard isSplit else { return TabBarClearance(hidden: 0, contentPadding: 0) }
        return TabBarClearance(hidden: max(barInset, 0) + gap, contentPadding: gap)
    }
}

/// Where the leading pane's content stops above the tab bar. A row the
/// clearance line would slice is hidden whole instead: the cut moves up to
/// that row's top, so the pane never shows half a card or a sliced glyph.
/// A section header goes with its first row, and a row that starts more
/// than `maxLift` above the line is sliced rather than empty the pane.
struct PaneCut: Equatable, Sendable {
    /// In the same space as the rows' frames.
    var y: CGFloat
    /// The cut runs between two rows of this card, so the card gets rounded
    /// bottom corners there, as if it ended. `nil` between cards.
    var card: Card?

    /// A card whose rows report one by one: its inset from the pane edge
    /// and its corner radius.
    struct Card: Equatable, Sendable {
        var inset: CGFloat
        var cornerRadius: CGFloat

        /// An inset grouped List section on the warm wash.
        static let groupedList = Card(inset: 20, cornerRadius: 26)
    }

    struct Row: Equatable, Sendable {
        var minY: CGFloat
        var maxY: CGFloat
        var card: Card?
        /// A section header: hidden with the row below it.
        var keepsWithNext = false
    }

    static let maxLift: CGFloat = 220
    /// How far above a hidden row a header can end and still be its header.
    static let headerReach: CGFloat = 40

    static func make(line: CGFloat, rows: some Sequence<Row>) -> PaneCut {
        let rows = Array(rows)
        let sliced = rows.filter { row in
            row.minY < line - 0.5 && row.maxY > line + 0.5 && line - row.minY <= maxLift
        }
        var cut = PaneCut(y: line, card: nil)
        if let first = sliced.min(by: { $0.minY < $1.minY }) {
            // A card row's separator sits on the row above, so cut a point higher.
            cut = PaneCut(y: first.minY - (first.card == nil ? 0 : 1), card: first.card)
        }
        // A header left alone above the cut goes too.
        while let header = rows.first(where: { row in
            row.keepsWithNext && row.minY < cut.y - 0.5
                && row.maxY <= cut.y + 1 && cut.y - row.maxY <= headerReach
        }) {
            cut = PaneCut(y: header.minY, card: nil)
        }
        return cut
    }
}

extension EnvironmentValues {
    /// The leading pane's row frames, for `PaneCut`. `nil` folded, so the
    /// phone layout does no bookkeeping while it scrolls.
    @Entry var paneRows: PaneRows? = nil
}

/// Row frames reported by `paneRow()` and read by the pane's mask.
@MainActor @Observable
final class PaneRows {
    var rows: [UUID: PaneCut.Row] = [:]
}

extension View {
    /// See `TabBarClearance` and `PaneCut`. The reminder editor's form uses
    /// it too, so its rows end whole above the home indicator. The mask stays in place folded
    /// (fully open there), so folding never rebuilds the tab. The wash
    /// behind it fills the strip the tab view would otherwise paint white,
    /// so the bar floats on the page colour, not on a cut-off row.
    func clearsFloatingTabBar(_ isSplit: Bool) -> some View {
        modifier(ClearsFloatingTabBar(isSplit: isSplit))
    }

    /// A whole card or line the pane cut hides rather than slices.
    /// `keepsWithNext` marks a section header, hidden with its first row.
    func paneRow(keepsWithNext: Bool = false) -> some View {
        modifier(PaneRowReporter(card: nil, keepsWithNext: keepsWithNext))
    }

    /// A row of an inset grouped List, reported through its row background,
    /// which fills the cell, padding included. Folded, just the background.
    func paneListRowBackground(_ color: Color) -> some View {
        modifier(PaneListRowBackground(color: color))
    }
}

private struct ClearsFloatingTabBar: ViewModifier {
    let isSplit: Bool
    @State private var barInset: CGFloat = 0
    @State private var rows = PaneRows()

    private var clearance: TabBarClearance {
        .make(isSplit: isSplit, barInset: barInset)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.paneRows, isSplit ? rows : nil)
            // Scroll content margins reach the scroll views inside each
            // tab's NavigationStack; safe-area padding here didn't.
            .contentMargins(.bottom, clearance.contentPadding, for: .scrollContent)
            .bottomScrollEdgeEffectHidden(isSplit)
            .mask {
                PaneCutMask(rows: rows, hidden: clearance.hidden, isSplit: isSplit)
                    .ignoresSafeArea()
            }
            .background(Color.bondBackgroundGradient.ignoresSafeArea())
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { barInset = $0 }
    }
}

private struct PaneCutMask: View {
    let rows: PaneRows
    let hidden: CGFloat
    let isSplit: Bool

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let cut = isSplit
                ? PaneCut.make(line: frame.maxY - hidden, rows: rows.rows.values)
                : PaneCut(y: frame.maxY, card: nil)
            let y = min(max(cut.y - frame.minY, 0), frame.height)
            let radius = cut.card.map { min($0.cornerRadius, y / 2) } ?? 0
            // Two overlapping shapes rather than one path, so no seam shows
            // where the straight part meets the rounded card bottom.
            ZStack(alignment: .top) {
                Rectangle().frame(height: y - radius)
                if radius > 0 {
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: radius,
                        bottomTrailingRadius: radius,
                        style: .continuous
                    )
                    .frame(height: radius * 2)
                    .padding(.horizontal, cut.card?.inset ?? 0)
                    .offset(y: y - radius * 2)
                }
            }
            .frame(width: frame.width, height: frame.height, alignment: .top)
        }
    }
}

private struct PaneRowReporter: ViewModifier {
    let card: PaneCut.Card?
    let keepsWithNext: Bool
    @Environment(\.paneRows) private var paneRows
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                let row = PaneCut.Row(minY: frame.minY, maxY: frame.maxY, card: card, keepsWithNext: keepsWithNext)
                if paneRows?.rows[id] != row { paneRows?.rows[id] = row }
            }
            .onDisappear { paneRows?.rows[id] = nil }
    }
}

private struct PaneListRowBackground: ViewModifier {
    let color: Color
    @Environment(\.paneRows) private var paneRows

    func body(content: Content) -> some View {
        content.listRowBackground(
            color.modifier(PaneRowReporter(card: paneRows == nil ? nil : .groupedList, keepsWithNext: false))
        )
    }
}

private extension View {
    @ViewBuilder
    func bottomScrollEdgeEffectHidden(_ hidden: Bool) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(hidden, for: .bottom)
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
    /// pane: disabling vertical bars on the whole root inset the app 42 pt
    /// from both display edges.
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
    let enabled: Bool
    let trailing: Trailing

    private var split: UnfoldedSplit? {
        guard enabled else { return nil }
        return UnfoldedSplit.make(width: geometry.width, isRegularWidth: horizontalSizeClass == .regular, fold: geometry.fold)
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
    }
}

extension View {
    /// `enabled: false` shows the screen as it is at every width.
    func unfoldedLeadingPane<Trailing: View>(
        enabled: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(UnfoldedLeadingPane(enabled: enabled, trailing: trailing()))
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
/// pane and the brand beside it, as onboarding does. Content that fills the
/// other pane itself (the reminder editor's live preview) passes
/// `splitsItself`. Everywhere else it is the ordinary sheet. A fold or unfold
/// mid-presentation re-presents it in the other style.
private struct UnfoldedSheet<SheetContent: View>: ViewModifier {
    @Environment(\.isUnfoldedSplit) private var isSplit
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let splitsItself: Bool
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isSplit ? .constant(false) : $isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .environment(\.paneRows, nil)
            }
            .fullScreenCover(isPresented: isSplit ? $isPresented : .constant(false), onDismiss: onDismiss) {
                sheetContent()
                    .environment(\.paneRows, nil)
                    .unfoldedLeadingPane(enabled: !splitsItself) { UnfoldedBrandPanel() }
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
        splitsItself: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(UnfoldedSheet(
            isPresented: isPresented,
            onDismiss: onDismiss,
            splitsItself: splitsItself,
            sheetContent: content
        ))
    }

    func unfoldedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        splitsItself: Bool = false,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        unfoldedSheet(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            onDismiss: onDismiss,
            splitsItself: splitsItself
        ) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}
