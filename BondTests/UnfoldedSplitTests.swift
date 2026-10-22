import CoreGraphics
import Testing

@testable import Bond

struct UnfoldedSplitTests {
    // MARK: — When to split

    @Test func compact_width_never_splits() {
        #expect(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 455.5...495.5) == nil)
    }

    @Test func folded_outer_display_stays_single() {
        #expect(UnfoldedSplit.make(width: 466, isRegularWidth: true, fold: nil) == nil)
    }

    @Test func regular_width_too_narrow_for_two_panes_stays_single() {
        // The unfolded Duo held in portrait: 669 pt can't hold two 360 pt panes.
        #expect(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil) == nil)
        #expect(UnfoldedSplit.make(width: 719, isRegularWidth: true, fold: nil) == nil)
    }

    // MARK: — Where the panes go

    @Test func panes_meet_the_fold_edges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 455.5...495.5)
        #expect(split == UnfoldedSplit(primaryWidth: 455.5, secondaryX: 495.5, secondaryWidth: 455.5))
    }

    @Test func zero_width_fold_splits_at_the_line() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 475.5...475.5)
        #expect(split == UnfoldedSplit(primaryWidth: 475.5, secondaryX: 475.5, secondaryWidth: 475.5))
    }

    @Test func no_fold_splits_evenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        #expect(split == UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    @Test func off_centre_fold_that_starves_a_pane_falls_back_to_even() {
        let split = UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 300...340)
        #expect(split == UnfoldedSplit(primaryWidth: 400, secondaryX: 400, secondaryWidth: 400))
    }

    @Test func every_split_leaves_two_usable_panes_inside_the_width() {
        for width in stride(from: CGFloat(720), through: 1400, by: 7.5) {
            let folds: [ClosedRange<CGFloat>?] = [nil, (width / 2 - 20)...(width / 2 + 20), 100...140]
            for fold in folds {
                let panes = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: fold)
                #expect(panes != nil)
                guard let panes else { continue }
                #expect(panes.primaryWidth >= UnfoldedSplit.minimumPaneWidth)
                #expect(panes.secondaryWidth >= UnfoldedSplit.minimumPaneWidth)
                #expect(panes.secondaryX >= panes.primaryWidth)
                #expect(panes.secondaryX + panes.secondaryWidth == width)
            }
        }
    }
}
