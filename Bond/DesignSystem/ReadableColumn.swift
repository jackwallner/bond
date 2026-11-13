import SwiftUI

/// Where the content column stops growing. A phone-width list stretched across
/// a 13-inch iPad puts a row's title and its time a screen apart.
enum BondColumn {
    /// Lists, forms and the Insights charts.
    static let list: CGFloat = 700
    /// Single-purpose pages: onboarding, pairing, the paywall.
    static let page: CGFloat = 560
}

private struct ReadableColumnMargins: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Scroll content margins reach every List, Form and ScrollView
            // below, pushed screens included, and leave the navigation bar and
            // scroll indicators at the screen edges.
            .contentMargins(.horizontal, max(0, (width - maxWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    /// Centres the scrolling content of everything below in a column of at most
    /// `maxWidth`. A no-op at phone widths.
    func readableColumn(maxWidth: CGFloat = BondColumn.list) -> some View {
        modifier(ReadableColumnMargins(maxWidth: maxWidth))
    }

    /// Large titles sit at the screen edge while the column is centred, so on
    /// iPad the title goes inline and centres over the column.
    func columnTitle() -> some View {
        navigationBarTitleDisplayMode(UIDevice.current.userInterfaceIdiom == .pad ? .inline : .automatic)
    }

    /// Centres a page that does not scroll in a column of at most `maxWidth`.
    func readablePage(maxWidth: CGFloat = BondColumn.page) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
